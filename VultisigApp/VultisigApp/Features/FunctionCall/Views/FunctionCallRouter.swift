//
//  FunctionCallRouter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

import SwiftUI

struct FunctionCallRouter {
    private let viewBuilder = FunctionCallRouteBuilder()

    @ViewBuilder
    func build(_ route: FunctionCallRoute) -> some View {
        switch route {
        case .details(let defaultCoin, let vault):
            viewBuilder.buildDetailsScreen(
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
