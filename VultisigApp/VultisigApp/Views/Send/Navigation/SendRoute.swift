//
//  SendRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

enum SendRoute: Hashable {
    case details(input: SendRouteInput)
    case verify(tx: SendTransaction, vault: Vault)
    case pairing(vault: Vault, tx: SendTransaction, keysignPayload: KeysignPayload, fastVaultPassword: String?)
    case keysign(input: KeysignInput, tx: SendTransaction)
    case done(vault: Vault, hash: String, chain: Chain, tx: SendTransaction)
}
