//
//  SendRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

enum SendRoute: Hashable {
    case details(coin: Coin?, hasPreselectedCoin: Bool, tx: LegacySendTransaction, vault: Vault)
    case verify(tx: LegacySendTransaction, vault: Vault)
    case pairing(vault: Vault, tx: LegacySendTransaction, keysignPayload: KeysignPayload, fastVaultPassword: String?)
    case keysign(input: KeysignInput, tx: LegacySendTransaction)
    case done(vault: Vault, hash: String, chain: Chain, tx: LegacySendTransaction, keysignPayload: KeysignPayload?)
    case coinPicker(coins: [Coin], tx: LegacySendTransaction)
    case transactionDetails(input: SendCryptoContent)
}
