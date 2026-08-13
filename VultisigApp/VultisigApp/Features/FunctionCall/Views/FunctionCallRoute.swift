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
    /// The legacy form screen. `preselected` names the operation the screen
    /// opens on, with both selectors hidden — a row that lands here has
    /// already made the choice the dropdown used to ask for.
    ///
    /// Optional only because the dropdown path still compiles behind it; no
    /// caller passes `nil` since the action list became the only entry, and
    /// both it and this screen die with the last migration.
    case details(defaultCoin: Coin?, vault: Vault, preselected: FunctionCallType?)
    case verify(tx: SendTransaction, vault: Vault)
    // pair → keysign → done live on the shared `SigningRoute`; verify
    // navigates into it (reusing the Send-family keysign/done screens).
    case functionTransaction(vault: Vault, transactionType: FunctionTransactionType)

    /// Where a descriptor goes. The one place a `FunctionActionDescriptor`
    /// becomes navigation, so a row's destination cannot drift from what the
    /// router builds for it.
    static func route(
        for destination: FunctionActionDescriptor.Destination,
        coin: Coin,
        vault: Vault
    ) -> FunctionCallRoute {
        switch destination {
        case .transaction(let transactionType):
            return .functionTransaction(vault: vault, transactionType: transactionType)
        case .legacyFunctionCall(let functionCallType):
            return .details(defaultCoin: coin, vault: vault, preselected: functionCallType)
        }
    }
}
