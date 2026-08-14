//
//  FunctionTransactionRouter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

import SwiftUI

struct FunctionTransactionRouter {
    private let viewBuilder = FunctionTransactionRouteBuilder()

    @ViewBuilder
    func build(_ route: FunctionTransactionRoute) -> some View {
        switch route {
        case .actions(let defaultCoin, let vault):
            viewBuilder.buildActionsScreen(
                defaultCoin: defaultCoin,
                vault: vault
            )
        case .verify(let tx, let vault):
            viewBuilder.buildVerifyScreen(tx: tx, vault: vault)
        case .functionTransaction(let vault, let transactionType):
            viewBuilder.buildFunctionTransactionScreen(
                vault: vault,
                transactionType: transactionType
            )
        }
    }
}
