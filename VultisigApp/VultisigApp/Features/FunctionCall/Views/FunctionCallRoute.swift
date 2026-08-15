//
//  FunctionCallRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

enum FunctionCallRoute: Hashable {
    /// Entry point. Resolves to the chain's action list, or straight to its
    /// only operation when the chain offers exactly one.
    case actions(defaultCoin: Coin?, vault: Vault)
    case verify(tx: SendTransaction, vault: Vault)
    // pair → keysign → done live on the shared `SigningRoute`; verify
    // navigates into it (reusing the Send-family keysign/done screens).
    case functionTransaction(vault: Vault, transactionType: FunctionTransactionType)

    /// Where a descriptor goes. The one place a `FunctionActionDescriptor`
    /// becomes navigation, so a row's destination cannot drift from what the
    /// router builds for it.
    static func route(
        for destination: FunctionActionDescriptor.Destination,
        vault: Vault
    ) -> FunctionCallRoute {
        switch destination {
        case .transaction(let transactionType):
            return .functionTransaction(vault: vault, transactionType: transactionType)
        }
    }
}
