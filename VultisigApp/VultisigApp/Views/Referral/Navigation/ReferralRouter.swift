//
//  ReferralRouter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

import SwiftUI

struct ReferralRouter {
    private let navigationRouter: NavigationRouter
    private let viewBuilder = ReferralRouteBuilder()

    init(navigationRouter: NavigationRouter) {
        self.navigationRouter = navigationRouter
    }

    @ViewBuilder
    func build(_ route: ReferralRoute) -> some View {
        switch route {
        case .initial:
            viewBuilder.buildInitialScreen()
        case .onboarding:
            viewBuilder.buildOnboardingScreen()
        case .referredCodeForm:
            viewBuilder.buildReferredCodeFormScreen()
        case .vaultSelection(let viewModel):
            viewBuilder.buildVaultSelectionScreen(viewModel: viewModel)
        case .createReferral:
            viewBuilder.buildTransactionFlowScreen(isEdit: false)
        case .editReferral:
            viewBuilder.buildTransactionFlowScreen(isEdit: true)
        case .main:
            viewBuilder.buildMainScreen()
        }
    }
}
