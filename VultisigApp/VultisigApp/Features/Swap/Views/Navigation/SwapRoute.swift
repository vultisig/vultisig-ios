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
    // The review is a sheet over the form (`KeysignReview.swap`), and
    // pair → keysign → done live on the shared `SigningRoute`, carrying
    // `vaultPubKeyECDSA` (not a live `Vault`) in `SigningTxContext.swap` so
    // the actor-isolation contract is kept.
    //
    // Limit orders take the same review and the same `SigningRoute` tail:
    // `SwapTransaction` carries a `limitContext: LimitOrderRecord?` that
    // flips the review and done into their limit-mode UI when non-nil.
}
