//
//  CircleRouter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 2025-12-19.
//

import SwiftUI

struct CircleRouter {
    private let navigationRouter: NavigationRouter
    private let viewBuilder = CircleRouteBuilder()

    init(navigationRouter: NavigationRouter) {
        self.navigationRouter = navigationRouter
    }

    @ViewBuilder
    func build(_ route: CircleRoute) -> some View {
        switch route {
        case .main(let vault):
            viewBuilder.buildMainScreen(vault: vault)
        case .deposit(let vault):
            viewBuilder.buildDepositScreen(vault: vault)
        case .withdraw(let vault):
            viewBuilder.buildWithdrawScreen(vault: vault)
        }
    }
}
