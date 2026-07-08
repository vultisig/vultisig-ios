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
    case fastKeysign(vaultPubKeyECDSA: String, keysignPayload: KeysignPayload, transaction: SwapTransaction, retrySignal: SwapRetrySignal, fastVaultPassword: String)
    case keysign(input: KeysignInput, transaction: SwapTransaction, retrySignal: SwapRetrySignal)
    case done(vaultPubKeyECDSA: String, hash: String, approveHash: String?, chain: Chain, transaction: SwapTransaction, progressLink: String?)
}
