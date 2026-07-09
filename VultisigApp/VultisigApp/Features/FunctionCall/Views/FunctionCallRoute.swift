//
//  FunctionCallRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

enum FunctionCallRoute: Hashable {
    case details(defaultCoin: Coin?, vault: Vault)
    case verify(tx: SendTransaction, vault: Vault)
    // pair → keysign → done live on the shared `SigningRoute`; verify
    // navigates into it (reusing the Send-family keysign/done screens).
    case functionTransaction(vault: Vault, transactionType: FunctionTransactionType)
}
