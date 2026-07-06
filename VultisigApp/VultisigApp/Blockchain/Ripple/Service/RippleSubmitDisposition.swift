//
//  RippleSubmitDisposition.swift
//  VultisigApp
//

import Foundation

/// Classification of an XRPL `submit` engine result into the action the
/// broadcast layer must take. Mirrors the SDK broadcast resolver
/// (vultisig-sdk `core/chain/tx/broadcast/resolvers/ripple.ts`): only
/// `tesSUCCESS` counts as an accepted broadcast, a small set of in-flight
/// codes is resolved by looking the transaction up by hash, and every other
/// engine result is the ledger's authoritative rejection at preflight and
/// must fail loudly instead of being returned as a txid that may never land.
enum RippleSubmitDisposition: Equatable {

    /// `tesSUCCESS` (or, defensively, a response missing `engine_result`)
    /// with the echoed deterministic hash: the transaction was accepted into
    /// the open ledger and the status poller can track it from here.
    case accepted(hash: String)

    /// The transaction may already be known to the network even though this
    /// submit was not applied. Resolve by querying the `tx` method for the
    /// echoed hash before deciding between success and failure.
    case verifyByHash(code: String, hash: String?, message: String?)

    /// The ledger's authoritative "no" at preflight (`tem*`/`tec*`/`tel*`/
    /// remaining `tef*`/`ter*`), or a success response missing the hash we
    /// need to track the transaction. Surface the real engine code — never
    /// report a hash for a transaction the ledger did not accept.
    case rejected(code: String, message: String?)

    /// Engine results resolved by hash lookup instead of failing outright:
    /// - `tefALREADY` / `tefPAST_SEQ`: this exact transaction (or its
    ///   sequence) was already applied or queued — a faster co-signing peer's
    ///   broadcast of the same signed blob probably landed first.
    /// - `terQUEUED`: the server queued the transaction to apply in a future
    ///   ledger — it is in flight, not rejected.
    static let verifyByHashCodes: Set<String> = ["tefALREADY", "tefPAST_SEQ", "terQUEUED"]

    /// Pure classification of a `submit` response. XRPL echoes
    /// `tx_json.hash` — the deterministic hash of the exact submitted blob —
    /// for every engine result, so a hash may be present even on rejection.
    static func classify(
        engineResult: String?,
        engineResultMessage: String?,
        hash: String?
    ) -> RippleSubmitDisposition {
        let trackableHash = hash.flatMap { $0.isEmpty ? nil : $0 }

        guard let engineResult, engineResult != "tesSUCCESS" else {
            // tesSUCCESS, or a malformed/legacy response without an engine
            // result (defensive default shared with the SDK resolver): treat
            // as accepted as long as there is a hash to track. A missing hash
            // means there is nothing to poll, so surface the failure instead
            // of persisting an empty txid as a fake success.
            guard let trackableHash else {
                return .rejected(code: engineResult ?? "unknown", message: engineResultMessage)
            }
            return .accepted(hash: trackableHash)
        }

        if verifyByHashCodes.contains(engineResult) {
            return .verifyByHash(code: engineResult, hash: trackableHash, message: engineResultMessage)
        }

        return .rejected(code: engineResult, message: engineResultMessage)
    }
}

/// Outcome of the `tx` lookup that resolves a `.verifyByHash` disposition.
/// Mirrors `RippleTransactionStatusProvider`'s reading of the same response:
/// only a validated ledger is final, a known-but-unvalidated transaction is
/// in flight, and anything unusable counts as not found (the lookup is a
/// safety net — it must never invent a new failure mode).
enum RippleTxLookupOutcome: Equatable {
    /// The transaction is in a validated ledger with `tesSUCCESS` — final success.
    case validatedSuccess
    /// The transaction is in a validated ledger with a non-tes result — final failure.
    case validatedFailure(code: String)
    /// The transaction is known to the server but not yet validated.
    case pending
    /// The transaction is unknown (`txnNotFound`), or the lookup response is
    /// unusable and carries no evidence about the transaction.
    case notFound

    /// Pure interpretation of a `tx` method response.
    static func interpret(_ response: RippleTransactionStatusResponse) -> RippleTxLookupOutcome {
        guard response.error == nil,
              let result = response.result,
              result.status != "error",
              result.error == nil else {
            return .notFound
        }

        guard result.validated == true else {
            return .pending
        }

        guard let meta = result.meta else {
            // Validated but no meta (older transactions): treated as success,
            // matching RippleTransactionStatusProvider.
            return .validatedSuccess
        }

        if meta.TransactionResult == "tesSUCCESS" {
            return .validatedSuccess
        }
        return .validatedFailure(code: meta.TransactionResult)
    }
}
