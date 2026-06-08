//
//  SendRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

enum SendRoute: Hashable {
    case details(seed: SendDetailsSeed)
    case verify(tx: SendTransaction, retrySignal: SendRetrySignal, vault: Vault, prebuiltKeysignPayload: KeysignPayload? = nil)
    case pairing(vault: Vault, tx: SendTransaction, retrySignal: SendRetrySignal, keysignPayload: KeysignPayload, fastVaultPassword: String?)
    case keysign(input: KeysignInput, tx: SendTransaction, retrySignal: SendRetrySignal)
    case done(vault: Vault, hash: String, chain: Chain, tx: SendTransaction?, keysignPayload: KeysignPayload?)
    case transactionDetails(input: TransactionDonePayload)
}
