//
//  KeysignReview.swift
//  VultisigApp
//
//  The review an initiator sees before signing, presented as a sheet over the
//  screen that built the transaction. Each case carries what that flow's
//  review needs, and keeps the vault convention of `SigningTxContext`:
//  Send/FunctionTransaction carry the live `Vault`, Swap carries
//  `Vault.pubKeyECDSA` and the live object is re-fetched on MainActor.
//

enum KeysignReview: Hashable, Identifiable {
    case send(tx: SendTransaction, retrySignal: SendRetrySignal, vault: Vault, prebuiltKeysignPayload: KeysignPayload? = nil)
    case swap(transaction: SwapTransaction, retrySignal: SwapRetrySignal, vaultPubKeyECDSA: String)
    case functionTransaction(tx: SendTransaction, vault: Vault)
    /// Perps: review only, signing disabled. See `PerpsReviewContent`.
    case perps(request: PerpsReviewRequest, vaultPubKeyECDSA: String)

    var id: Self { self }

    /// Perps reviews match the other perps sheets: system dim, no root blur.
    var usesQuietBackdrop: Bool {
        if case .perps = self { return true }
        return false
    }
}
