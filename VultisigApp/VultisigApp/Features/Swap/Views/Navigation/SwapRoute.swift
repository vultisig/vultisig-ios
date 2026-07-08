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
    // pair → keysign → done live on the shared `SigningRoute`; verify
    // navigates into it, carrying `vaultPubKeyECDSA` (not a live `Vault`)
    // in `SigningTxContext.swap` so the actor-isolation contract is kept.
}
