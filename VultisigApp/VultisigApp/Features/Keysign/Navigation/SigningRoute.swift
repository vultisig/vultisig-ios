//
//  SigningRoute.swift
//  VultisigApp
//
//  Shared tail-end signing route for every keysign-side flow (Send, Swap,
//  FunctionCall). The signing screens (`PairScreen`, `KeysignView`,
//  `DoneScreen`) are already single shared components; this collapses the
//  `pair → fastKeysign → keysign → done` ROUTING that each flow used to
//  re-declare in its own `*Route` enum + builder + router. Each flow's
//  per-flow `verify` screen navigates INTO these cases.
//
//  The flow-specific variance is folded behind two value enums so no flow
//  loses any data:
//    - `SigningTxContext` threads the transaction identity + retry signal
//      from verify through pair/keysign so the done route can be rebuilt.
//    - `DoneKind` carries each flow's done-screen inputs.
//
//  Vault convention: Send/FunctionCall carry the live `Vault` (as their
//  routes always have). Swap deliberately carries `Vault.pubKeyECDSA` and
//  re-fetches the live object in `SigningRouter` — a `Vault` is a SwiftData
//  `@Model` that must not escape its `ModelContext`'s actor across the
//  `NavigationPath`.
//

enum SigningRoute: Hashable {
    case pair(context: SigningTxContext, keysignPayload: KeysignPayload, fastVaultPassword: String?)
    case fastKeysign(context: SigningTxContext, keysignPayload: KeysignPayload, fastVaultPassword: String)
    case keysign(input: KeysignInput, context: SigningTxContext)
    case done(DoneKind)
}

/// Flow-specific transaction identity threaded from `verify` through
/// `pair`/`fastKeysign` into `keysign`, so the keysign screen can rebuild
/// the `done` route and pop back to `verify` on a retryable broadcast
/// failure. Keeps each flow's existing vault convention (Send/FunctionCall
/// carry the live `Vault`; Swap carries `pubKeyECDSA` and re-fetches).
enum SigningTxContext: Hashable {
    case send(vault: Vault, tx: SendTransaction, retry: SendRetrySignal)
    case functionCall(vault: Vault, tx: SendTransaction, retry: SendRetrySignal)
    case swap(vaultPubKeyECDSA: String, transaction: SwapTransaction, retry: SwapRetrySignal)
}

extension SigningTxContext {
    /// QR-share preview flavor for the pairing screen — swaps get the swap
    /// hero, everything else gets the send hero.
    var previewType: QRShareSheetType {
        switch self {
        case .swap:
            return .Swap
        case .send, .functionCall:
            return .Send
        }
    }

    /// The live swap transaction that drives the swap pairing preview; `nil`
    /// for the send-family flows.
    var swapTransaction: SwapTransaction? {
        if case .swap(_, let transaction, _) = self {
            return transaction
        }
        return nil
    }

    /// Send-only pairing preview override: surfaces the display `tx`'s amount
    /// + recipient when the signed payload's coin differs (e.g. a Circle USDC
    /// withdraw signing a native-ETH MSCA call). Returns `nil` for the swap
    /// and function-call flows, matching their previous per-flow pair screens.
    func sendPreviewOverride(payload: KeysignPayload) -> SendPreviewOverride? {
        if case .send(_, let tx, _) = self {
            return SendPreviewOverride.makeIfNeeded(displayTx: tx, signedPayload: payload)
        }
        return nil
    }
}

/// Done-screen inputs, folded per flow so the shared `done` route carries
/// every field each flow needs (Send's `tx`/`keysignPayload`; Swap's
/// `approveHash`/`progressLink`). FunctionCall reuses `.send`, as it always
/// piggybacked on the Send done screen.
enum DoneKind: Hashable {
    case send(vault: Vault, hash: String, chain: Chain, tx: SendTransaction?, keysignPayload: KeysignPayload?)
    case swap(vaultPubKeyECDSA: String, hash: String, approveHash: String?, chain: Chain, transaction: SwapTransaction, progressLink: String?)
}
