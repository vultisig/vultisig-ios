//
//  SendRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

enum SendRoute: Hashable {
    case details(seed: SendDetailsSeed)
    case verify(tx: SendTransaction, retrySignal: SendRetrySignal, vault: Vault, prebuiltKeysignPayload: KeysignPayload? = nil)
    // pairing → keysign → done live on the shared `SigningRoute`; verify
    // navigates into it. Only the pre-signing screens stay Send-specific.
    case transactionDetails(input: TransactionDonePayload)
}
