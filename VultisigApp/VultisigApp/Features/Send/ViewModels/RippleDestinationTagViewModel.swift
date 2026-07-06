//
//  RippleDestinationTagViewModel.swift
//  VultisigApp
//
//  XRP-only Destination Tag sub-view-model, extracted from
//  `SendDetailsViewModel` so the shared send form stays free of the
//  Ripple-specific tag concern. Owns the tag field state, the X-address
//  autofill/lock lifecycle, and the RequireDest gate bookkeeping.
//
//  Decision logic is exposed as return-typed methods that take the shared
//  send-form inputs (`memo`, `toAddress`) as parameters and never reach
//  back into the parent: the parent maps the returned outcomes onto its own
//  shared error banner, and threads the sub-VM into `validateForm()` /
//  `makeTransaction()`.
//

import Foundation
import Observation

@MainActor
@Observable
final class RippleDestinationTagViewModel {

    /// Asks the caller to surface the parent's shared error banner. Empty for
    /// the success case.
    enum TagMemoValidation: Equatable {
        case valid
        case invalidTag
        case memoNotTag
        case tagMemoConflict

        var errorKey: String? {
            switch self {
            case .valid: return nil
            case .invalidTag: return "destinationTagInvalidError"
            case .memoNotTag: return "xrpMemoNotDestinationTagError"
            case .tagMemoConflict: return "destinationTagMemoConflictError"
            }
        }
    }

    /// Outcome of the RequireDest pre-send gate. The sub-VM performs its own
    /// state side effects (nudge bump, alert flag); the parent decides how to
    /// surface the shared error banner and how the form pipeline proceeds.
    enum RequireDestOutcome: Equatable {
        /// A present tag satisfies the flag, or the destination doesn't
        /// require one — proceed.
        case satisfied
        /// Destination requires a tag and none is set — hard block. The field
        /// nudge was already bumped.
        case required
        /// Lookup couldn't verify and the user hasn't acknowledged the risk
        /// for this address — block pending acknowledgment. The alert flag
        /// was already set.
        case unverified
    }

    @ObservationIgnored private let requirementProvider: (String) async -> RippleDestinationTagRequirement

    /// XRP destination tag, kept as the raw field text. Validated by
    /// `validateTagAndMemo(memo:)` and resolved against the memo by
    /// `resolvedTag(memo:)` when the immutable transaction is built.
    var destinationTag: String = ""

    /// True when `destinationTag` was derived from a pasted X-address — the
    /// field is read-only then, because the tag is part of the address the
    /// sender was given and editing it would misroute the deposit.
    var isDestinationTagLocked: Bool = false

    /// Asks the screen to present the "couldn't verify whether this address
    /// requires a destination tag" two-button confirm (Continue anyway /
    /// Cancel) — the explicit-acknowledgment half of the fail-open posture.
    var showDestinationTagUnverifiedAlert: Bool = false

    /// Incremented when the RequireDest gate hard-blocks a tagless send so
    /// the additional-fields section can expand the (empty, collapsed) tag
    /// field the user now has to fill.
    private(set) var destinationTagFieldNudge: Int = 0

    /// Session-scoped cache of RequireDest lookups so repeated Continue
    /// presses don't re-query. `.unknown` is never cached — a failed lookup
    /// retries next time.
    @ObservationIgnored private var requirementCache: [String: RippleDestinationTagRequirement] = [:]

    /// Address the user explicitly accepted the unverified-RequireDest risk
    /// for. Keyed by address so the acknowledgment can't leak onto a
    /// different destination.
    @ObservationIgnored private var unverifiedAckAddress: String?

    init(requirementProvider: ((String) async -> RippleDestinationTagRequirement)? = nil) {
        self.requirementProvider = requirementProvider ?? { address in
            await RippleService.shared.fetchDestinationTagRequirement(for: address)
        }
    }

    // MARK: - X-address autofill / lock lifecycle

    /// Apply the tag embedded in a decoded X-address. A present tag autofills
    /// and locks the field; no embedded tag releases any prior lock and
    /// clears the stale locked value.
    func applyDecodedTag(_ tag: UInt32?) {
        guard let tag else {
            releaseLockedTag()
            return
        }
        destinationTag = String(tag)
        isDestinationTagLocked = true
    }

    /// The destination input is no longer the X-address that locked the tag.
    /// When it also changed away from the locked classic address, the derived
    /// tag belonged to the old destination — drop it.
    func handleAddressChangedAway(isStillResolved: Bool) {
        guard !isStillResolved else { return }
        releaseLockedTag()
    }

    /// Drop an X-address-derived (locked) tag and release the lock. A
    /// manually-typed tag on an unlocked field is left untouched.
    func releaseLockedTag() {
        guard isDestinationTagLocked else { return }
        isDestinationTagLocked = false
        destinationTag = ""
    }

    /// Chain switched to one without destination-tag support — drop any tag
    /// (typed or locked) so it can't ride along invisibly.
    func clearForUnsupportedChain() {
        destinationTag = ""
        isDestinationTagLocked = false
    }

    // MARK: - Tag / memo contract

    /// XRP tag/memo contract:
    /// - the tag field must be empty or a canonical uint32 decimal;
    /// - the memo must be empty or canonical numeric (the legacy "type the
    ///   tag into the memo" workaround), else it's steered to the tag field;
    /// - both set with different values is a conflict (the wire carries one).
    func validateTagAndMemo(memo: String) -> TagMemoValidation {
        var fieldTag: UInt32?
        if !destinationTag.isEmpty {
            guard let tag = RippleDestinationTag.parseTag(destinationTag) else {
                return .invalidTag
            }
            fieldTag = tag
        }

        if !memo.isEmpty {
            guard RippleDestinationTag.parseCanonical(memo) != nil else {
                return .memoNotTag
            }
            guard let memoTag = RippleDestinationTag.parseTag(memo) else {
                // Numeric but zero — same rejection as the field.
                return .invalidTag
            }
            if let fieldTag, memoTag != fieldTag {
                return .tagMemoConflict
            }
        }

        return .valid
    }

    /// Effective destination tag: the dedicated field wins; a canonical
    /// numeric memo (legacy workaround) is honored when the field is empty.
    /// Only meaningful after `validateTagAndMemo(memo:)` passed.
    func resolvedTag(memo: String) -> UInt32? {
        if let tag = RippleDestinationTag.parseTag(destinationTag) {
            return tag
        }
        return RippleDestinationTag.parseTag(memo)
    }

    // MARK: - RequireDest gate

    /// RequireDest gate: a tagless XRP send to a destination whose
    /// AccountRoot sets `lsfRequireDestTag` is hard-blocked; a failed lookup
    /// fails OPEN behind an explicit per-address acknowledgment. Definitive
    /// results are cached per address; `.unknown` is never cached so a failed
    /// lookup retries.
    func validateRequireDest(toAddress: String, memo: String) async -> RequireDestOutcome {
        // A present tag (field or legacy numeric memo) satisfies the flag.
        guard resolvedTag(memo: memo) == nil else { return .satisfied }

        let requirement: RippleDestinationTagRequirement
        if let cached = requirementCache[toAddress] {
            requirement = cached
        } else {
            requirement = await requirementProvider(toAddress)
            if requirement != .unknown {
                requirementCache[toAddress] = requirement
            }
        }

        switch requirement {
        case .required:
            destinationTagFieldNudge += 1
            return .required
        case .notRequired, .accountNotFound:
            return .satisfied
        case .unknown:
            if unverifiedAckAddress == toAddress {
                return .satisfied
            }
            showDestinationTagUnverifiedAlert = true
            return .unverified
        }
    }

    /// Records the user's "Continue anyway" on the unverified-RequireDest
    /// confirm for the given destination.
    func acknowledge(toAddress: String) {
        unverifiedAckAddress = toAddress
    }

    // MARK: - Reset

    /// Clear the tag state for a fresh send. Mirrors the fields the parent's
    /// `reset(to:)` cleared for the tag — the requirement cache and nudge are
    /// intentionally left intact (unchanged from the pre-extraction behavior).
    func reset() {
        destinationTag = ""
        isDestinationTagLocked = false
        showDestinationTagUnverifiedAlert = false
        unverifiedAckAddress = nil
    }
}
