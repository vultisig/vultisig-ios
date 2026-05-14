//
//  SwapRoute.swift
//  VultisigApp
//
//  `Vault` and `Coin` are SwiftData `@Model` classes that must never escape
//  their `ModelContext`'s actor. We pass stable identifiers (`Vault.pubKeyECDSA`,
//  `Coin.id`) instead and re-fetch the live objects in `SwapRouter.build(_:)`
//  before handing them to the screens. See johnnyluo's review on PR #4331.
//

enum SwapRoute: Hashable {
    case root(fromCoinID: String?, toCoinID: String?, vaultPubKeyECDSA: String)
    case verify(transaction: SwapTransaction, retrySignal: SwapRetrySignal, vaultPubKeyECDSA: String)
    case pair(vaultPubKeyECDSA: String, transaction: SwapTransaction, retrySignal: SwapRetrySignal, keysignPayload: KeysignPayload, fastVaultPassword: String?)
    case keysign(input: KeysignInput, transaction: SwapTransaction, retrySignal: SwapRetrySignal)
    case done(vaultPubKeyECDSA: String, hash: String, approveHash: String?, chain: Chain, transaction: SwapTransaction, progressLink: String?)

    // MARK: - Limit-swap pipeline
    //
    // Post-place-order pipeline for the limit-swap flow. Carries
    // `LimitOrderRecord` instead of `SwapTransaction` because limit orders
    // have no market quote — they are memo-only deposits to THORChain.
    // Reuses the existing `KeysignDiscoveryView` / `KeysignView`
    // underneath the limit-specific Pair / Keysign screens. The details
    // screen itself is the standard `SwapDetailsScreen` with a
    // Market/Limit toggle that swaps the body in place — no route for it.
    case limitPair(vaultPubKeyECDSA: String, keysignPayload: KeysignPayload, pendingRecord: LimitOrderRecord)
    case limitKeysign(input: KeysignInput, pendingRecord: LimitOrderRecord)
    case limitDone(vaultPubKeyECDSA: String, hash: String, chain: Chain, pendingRecord: LimitOrderRecord)
}
