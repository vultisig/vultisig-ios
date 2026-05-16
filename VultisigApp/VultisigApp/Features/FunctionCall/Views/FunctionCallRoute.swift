//
//  FunctionCallRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

enum FunctionCallRoute: Hashable {
    case details(defaultCoin: Coin?, sendTx: FunctionCallForm, vault: Vault)
    case verify(tx: SendTransaction, vault: Vault)
    case pair(vault: Vault, tx: SendTransaction, keysignPayload: KeysignPayload, fastVaultPassword: String?)
    case keysign(input: KeysignInput, tx: SendTransaction, retrySignal: SendRetrySignal)
    case functionTransaction(vault: Vault, transactionType: FunctionTransactionType)
}
