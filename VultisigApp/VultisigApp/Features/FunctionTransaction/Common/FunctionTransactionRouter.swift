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
        case .functionTransaction(let vault, let transactionType):
            viewBuilder.buildFunctionTransactionScreen(
                vault: vault,
                transactionType: transactionType
            )
        }
    }
}
