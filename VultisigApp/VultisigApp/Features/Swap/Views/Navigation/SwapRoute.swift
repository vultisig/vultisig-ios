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
    case verify(tx: SwapTransaction, vaultPubKeyECDSA: String)
    case pair(vaultPubKeyECDSA: String, tx: SwapTransaction, keysignPayload: KeysignPayload, fastVaultPassword: String?)
    case keysign(input: KeysignInput, tx: SwapTransaction)
    case done(vaultPubKeyECDSA: String, hash: String, approveHash: String?, chain: Chain, tx: SwapTransaction, progressLink: String?)
}
