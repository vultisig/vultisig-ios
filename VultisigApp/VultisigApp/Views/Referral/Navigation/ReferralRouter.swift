//
//  ReferralRouter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

import SwiftUI

struct ReferralRouter {
    private let viewBuilder = ReferralRouteBuilder()

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
        case .createReferral(let viewModel):
            viewBuilder.buildTransactionFlowScreen(viewModel: viewModel, thornameDetails: nil, currentBlockheight: 0)
        case .editReferral(let viewModel, let thornameDetails, let currentBlockheight):
            viewBuilder.buildTransactionFlowScreen(viewModel: viewModel, thornameDetails: thornameDetails, currentBlockheight: currentBlockheight)
        case .main:
            viewBuilder.buildMainScreen()
        }
    }
}
