//
//  ExternalRecipientViewModel.swift
//  VultisigApp
//
//  Owns the external-recipient input state for the advanced-swap sub-sheet:
//  the raw text field, name resolution (ENS `.eth` for EVM, THORName/TNS for
//  THORChain/Maya, etc.) and validation for the destination chain. Resolution
//  + validation are kept out of the View per the architecture rules. The
//  resolved (never the raw name) address is what gets persisted as the swap's
//  external recipient, so an unresolvable/invalid entry can never reach signing.
//

import OSLog
import SwiftUI

@MainActor
@Observable
final class ExternalRecipientViewModel {
    @ObservationIgnored private let logger = Logger(subsystem: "com.vultisig.app", category: "external-recipient")

    /// Resolves a literal address or a name (ENS/TNS/THORName) to a validated
    /// on-chain address for the given chain, throwing when it can't. Injected so
    /// tests can drive resolution deterministically; defaults to the same
    /// resolver the Send flow uses.
    @ObservationIgnored private let resolver: (String, Chain) async throws -> String

    @ObservationIgnored private var resolveTask: Task<Void, Never>?

    /// The last value we already resolved+persisted. Writing the resolved address
    /// back into `input` re-fires the view's `onChange`; this guard makes that
    /// pass a no-op so a successful resolution doesn't trigger a redundant fetch.
    @ObservationIgnored private var lastResolvedInput: String?

    /// The destination chain the recipient is validated/resolved against.
    @ObservationIgnored private let chain: Chain

    /// `FormField` drives validation state/errors from the form layer rather than
    /// inline ad-hoc checks. The `AddressValidator` rejects a non-empty value that
    /// isn't a valid address for `chain`; an empty value is allowed (clears the
    /// recipient → own-address swap). `FormField` is a Combine `ObservableObject`,
    /// so it's kept `@ObservationIgnored`: the view observes the mirrored
    /// `@Observable` `input` / `error` / `isResolving` below, not the field directly.
    @ObservationIgnored let field: FormField

    /// The raw text the field renders and resolution runs against. Mirrored onto
    /// the backing `FormField` on write so the validator/form state stay in sync
    /// while SwiftUI observes this `@Observable` property.
    var input: String {
        didSet { field.value = input }
    }

    /// True while a name is being resolved to an address.
    var isResolving = false

    /// When a name resolved to an address, the original name to show as a label
    /// (e.g. "vitalik.eth"). `nil` when the input was already a literal address.
    var resolvedNameLabel: String?

    /// Inline error surfaced to the user (invalid address / name not found),
    /// mirrored from the form field so SwiftUI observes it.
    var error: String?

    init(
        chain: Chain,
        initialRecipient: String?,
        resolver: @escaping (String, Chain) async throws -> String = AddressService.resolveInput
    ) {
        self.chain = chain
        self.resolver = resolver
        let initial = initialRecipient ?? .empty
        self.input = initial
        self.field = FormField(
            initialValue: initial,
            label: "sendToDifferentAddress".localized,
            validators: [AddressValidator(chain: chain)]
        )
    }

    /// Mirror an accessory action's result (paste / QR / address book) into the
    /// field so it flows through the same resolve + validate path.
    func apply(address: String) {
        input = address
    }

    /// Debounced resolve-and-validate. Cancels any in-flight resolution. Writes
    /// the validated, resolved address back through `persist` on success; clears
    /// it (and the field error stays per the form) on failure. An empty field
    /// clears the recipient with no error.
    func resolveAndPersist(persist: @escaping (String?) -> Void) {
        resolveTask?.cancel()

        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.isNotEmpty else {
            // Empty input: own-address swap. No error, no name label.
            isResolving = false
            resolvedNameLabel = nil
            lastResolvedInput = nil
            setError(nil)
            field.valid = true
            persist(nil)
            return
        }

        // Writing a resolved address back into `input` re-enters here; skip the
        // redundant resolution when nothing actually changed.
        guard raw != lastResolvedInput else {
            isResolving = false
            return
        }

        isResolving = true
        resolveTask = Task { [weak self] in
            guard let self else { return }
            // Short debounce so each keystroke doesn't fire a network resolution.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            do {
                let resolved = try await resolver(raw, chain)
                guard !Task.isCancelled else { return }
                isResolving = false
                // A name resolved to a different address — surface the name as the
                // label so the user sees what they typed alongside the address.
                resolvedNameLabel = (resolved != raw) ? raw : nil
                lastResolvedInput = resolved
                input = resolved
                setError(nil)
                field.valid = true
                persist(resolved)
            } catch {
                guard !Task.isCancelled else { return }
                isResolving = false
                resolvedNameLabel = nil
                logger.debug("External recipient resolution failed: \(error.localizedDescription)")
                // Distinguish a name lookup miss from an outright invalid address
                // so the user knows whether to retry a name.
                setError(raw.containsNameService
                    ? "recipientNameNotFound".localized
                    : "validAddressError".localized)
                field.valid = false
                // An invalid/unresolvable entry must never persist — it can't reach signing.
                persist(nil)
            }
        }
    }

    /// Set the inline error on both the mirrored `@Observable` property (what the
    /// view observes) and the backing form field (the form-layer source of truth).
    private func setError(_ message: String?) {
        error = message
        field.error = message
    }

    func cancel() {
        resolveTask?.cancel()
        isResolving = false
    }
}

private extension String {
    /// Whether the input looks like a name to resolve (ENS/`.sol` or a THORName)
    /// rather than a literal address — used only to pick the right error copy.
    var containsNameService: Bool {
        isENSNameService() || (!contains("0x") && contains("."))
    }
}
