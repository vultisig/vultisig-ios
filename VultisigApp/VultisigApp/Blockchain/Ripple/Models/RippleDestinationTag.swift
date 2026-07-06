//
//  RippleDestinationTag.swift
//  VultisigApp
//

import Foundation

/// Destination-tag rules for XRP keysign payloads.
///
/// The tag travels in the generic `KeysignPayload.memo` slot as a canonical
/// uint32 decimal — the wire contract every Vultisig platform's Ripple
/// signing-input builder already understands (numeric memo → wallet-core
/// `destinationTag`). "Canonical" matters: leading zeros or whitespace make
/// the SDK's strict round-trip parse diverge from the lenient mobile parses,
/// which would split the keysign committee's pre-image hashes.
///
/// The payload memo must therefore be empty or a canonical uint32 decimal;
/// anything else is rejected on BOTH sides of the ceremony (initiator and
/// co-signer both funnel through `RippleHelper.getPreSignedInputData`).
/// This intentionally removes the legacy non-numeric-memo → on-chain
/// `Memos` blob path: a tag-typo there meant an uncredited exchange deposit.
enum RippleDestinationTag {

    /// Strict canonical parse: ASCII digits only, no sign, no whitespace,
    /// no leading zeros (except the value "0" itself), and within uint32
    /// bounds. The round-trip comparison enforces all of that at once.
    static func parseCanonical(_ string: String) -> UInt32? {
        guard let value = UInt32(string), String(value) == string else {
            return nil
        }
        return value
    }

    /// Parse a destination tag: canonical AND non-zero. Zero is rejected
    /// because wallet-core's proto3 scalar can't express "present with value
    /// 0" — the payment would sign untagged on every platform while the UI
    /// displayed a tag. (XLS-5d allows tag 0 on-chain; no wallet-core-based
    /// signer can produce it, so failing loudly beats signing dishonestly.)
    static func parseTag(_ string: String) -> UInt32? {
        guard let value = parseCanonical(string), value != 0 else {
            return nil
        }
        return value
    }

    /// Validates the memo slot of an XRP keysign payload. Returns the tag
    /// (or `nil` for an empty memo) or throws `RippleMemoError.invalidMemo`.
    static func validatePayloadMemo(_ memo: String?) throws -> UInt32? {
        guard let memo, !memo.isEmpty else { return nil }
        guard let tag = parseTag(memo) else {
            throw RippleMemoError.invalidMemo(memo)
        }
        return tag
    }

    /// Field-preferred destination tag for DISPLAY on the co-signer/verify
    /// screen — scoped to plain XRP PAYMENTS, whose tag was previously shown as
    /// a numeric memo. Non-throwing: yields `nil` (no row) when there's no
    /// displayable tag. Returns `nil` for non-XRP.
    ///
    /// Swaps are intentionally excluded: their memo carries protocol routing
    /// (THORChain text memo → on-chain Memos blob) or a SwapKit tag, the signer
    /// resolves them from the memo with different rules, and they keep their
    /// existing memo-row display unchanged — so a swap never gets a Destination
    /// Tag row here (no risk of displaying a tag that differs from the signed
    /// one, or of hiding a routing memo).
    ///
    /// A present field is terminal, mirroring the signer: a nonzero field is
    /// the tag; a malformed 0 field is not displayable (and won't sign), so it
    /// does NOT fall through to the memo.
    static func displayTag(for payload: KeysignPayload) -> UInt32? {
        guard payload.coin.chain == .ripple, payload.swapPayload == nil else { return nil }
        if case .Ripple(_, _, _, let fieldTag) = payload.chainSpecific, let fieldTag {
            return fieldTag == 0 ? nil : fieldTag
        }
        return payload.memo.flatMap(parseTag)
    }

    /// Genuine on-chain TEXT memo to display for a plain XRP PAYMENT — the
    /// tag+memo combo, or a memo-only send. Returns `nil` when the memo slot is
    /// a numeric destination-tag carrier (echo / legacy workaround), for swaps,
    /// and for non-XRP: those either surface via the Destination Tag row or keep
    /// their own memo handling. Mirrors the signer, which routes exactly these
    /// text memos to an on-chain `Memos` blob — so a co-signer sees the same
    /// memo it is about to sign.
    static func displayMemo(for payload: KeysignPayload) -> String? {
        guard payload.coin.chain == .ripple, payload.swapPayload == nil else { return nil }
        guard let memo = payload.memo, !memo.isEmpty else { return nil }
        // A canonical uint32 decimal is a tag carrier, not text.
        guard parseCanonical(memo) == nil else { return nil }
        return memo
    }
}

/// Typed, user-presentable rejection for XRP payloads whose memo slot
/// doesn't satisfy the destination-tag wire contract. Surfaced by the
/// initiator when the ceremony is prepared and by co-signers before they
/// join it (dApp/deeplink-originated payloads included).
enum RippleMemoError: LocalizedError, Equatable {
    case invalidMemo(String)
    /// A plain payment carried BOTH a first-class tag field AND a memo slot
    /// holding a DIFFERENT canonical number — the two would read as conflicting
    /// destination tags. Only reachable via a malformed/hand-crafted payload
    /// (the form blocks it); the signer rejects it deterministically rather than
    /// pick one.
    case tagMemoConflict(tag: UInt32, memo: String)

    var errorDescription: String? {
        switch self {
        case .invalidMemo:
            return "xrpMemoNotDestinationTagError".localized
        case .tagMemoConflict:
            return "destinationTagMemoConflictError".localized
        }
    }
}
