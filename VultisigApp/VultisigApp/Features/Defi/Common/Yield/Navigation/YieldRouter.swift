//
//  YieldRouter.swift
//  VultisigApp
//

import SwiftUI

struct YieldRouter {
    private let viewBuilder = YieldRouteBuilder()

    @MainActor
    @ViewBuilder
    func build(_ route: YieldRoute) -> some View {
        switch route {
        case .main(let vault, let providerID):
            viewBuilder.buildMainScreen(vault: vault, providerID: providerID)
        case .deposit(let vault, let providerID):
            viewBuilder.buildDepositScreen(vault: vault, providerID: providerID)
        case .withdraw(let vault, let providerID, let model):
            viewBuilder.buildWithdrawScreen(vault: vault, providerID: providerID, model: model)
        }
    }
}
