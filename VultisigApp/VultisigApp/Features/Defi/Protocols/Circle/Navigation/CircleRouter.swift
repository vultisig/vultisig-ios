//
//  CircleRouter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 2025-12-19.
//

import SwiftUI

struct CircleRouter {
    private let viewBuilder = CircleRouteBuilder()

    @ViewBuilder
    func build(_ route: CircleRoute) -> some View {
        switch route {
        case .main(let vault):
            viewBuilder.buildMainScreen(vault: vault)
        case .deposit(let vault):
            viewBuilder.buildDepositScreen(vault: vault)
        case .withdraw(let vault, let model):
            viewBuilder.buildWithdrawScreen(vault: vault, model: model)
        }
    }
}
