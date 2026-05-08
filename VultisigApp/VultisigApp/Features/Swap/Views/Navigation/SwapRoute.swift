//
//  SwapRoute.swift
//  VultisigApp
//

enum SwapRoute: Hashable {
    case root(fromCoin: Coin?, toCoin: Coin?, vault: Vault)
    case verify(tx: SwapTransaction, vault: Vault)
    case pair(vault: Vault, tx: SwapTransaction, keysignPayload: KeysignPayload, fastVaultPassword: String?)
    case keysign(input: KeysignInput, tx: SwapTransaction)
    case done(vault: Vault, hash: String, approveHash: String?, chain: Chain, tx: SwapTransaction, progressLink: String?)
}
