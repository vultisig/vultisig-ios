//
//  SendRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

enum SendRoute: Hashable {
    case details(coin: Coin?, hasPreselectedCoin: Bool, tx: SendTransaction, vault: Vault)
    case verify(tx: SendTransaction, vault: Vault)
    case pairing(vault: Vault, tx: SendTransaction, keysignPayload: KeysignPayload)
    case keysign(input: KeysignInput, tx: SendTransaction)
    case done(vault: Vault, hash: String, chain: Chain, tx: SendTransaction, keysignPayload: KeysignPayload?)
    case coinPicker(coins: [Coin], tx: SendTransaction)
    case transactionDetails(input: SendCryptoContent)
}
