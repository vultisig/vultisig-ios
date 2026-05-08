//
//  SwapRoute.swift
//  VultisigApp
//

enum SwapRoute: Hashable {
    case root(fromCoin: Coin?, toCoin: Coin?, vault: Vault)
    case verify(transaction: SwapTransaction, retrySignal: SwapRetrySignal, vault: Vault)
    case pair(vault: Vault, transaction: SwapTransaction, retrySignal: SwapRetrySignal, keysignPayload: KeysignPayload, fastVaultPassword: String?)
    case keysign(input: KeysignInput, transaction: SwapTransaction, retrySignal: SwapRetrySignal)
    case done(vault: Vault, hash: String, approveHash: String?, chain: Chain, transaction: SwapTransaction, progressLink: String?)
}
