//
//  FunctionTransactionRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//
//  Renamed from `FunctionCallRoute`. It was never the legacy screen's route —
//  it is the shared seam every operation reaches Verify through, and the DeFi
//  tab, Referral and the limit-order cancel all navigate it without ever
//  touching a `FunctionCall*` type. The old name only ever described the one
//  producer that has since been deleted.
//

enum FunctionTransactionRoute: Hashable {
    case verify(tx: SendTransaction, vault: Vault)
    // pair → keysign → done live on the shared `SigningRoute`; verify
    // navigates into it (reusing the Send-family keysign/done screens).
    case functionTransaction(vault: Vault, transactionType: FunctionTransactionType)

    /// Where a descriptor goes. The one place a `FunctionActionDescriptor`
    /// becomes navigation, so a row's destination cannot drift from what the
    /// router builds for it.
    static func route(
        for destination: FunctionTransactionType,
        vault: Vault
    ) -> FunctionTransactionRoute {
        .functionTransaction(vault: vault, transactionType: destination)
    }
}
