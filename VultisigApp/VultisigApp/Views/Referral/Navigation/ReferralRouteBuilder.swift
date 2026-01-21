//
//  ReferralRouteBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

import SwiftUI

struct ReferralRouteBuilder {

    @ViewBuilder
    func buildInitialScreen() -> some View {
        ReferralInitialScreen()
    }

    @ViewBuilder
    func buildOnboardingScreen() -> some View {
        ReferredOnboardingView()
    }

    @ViewBuilder
    func buildMainScreen() -> some View {
        ReferralMainScreen()
    }

    @ViewBuilder
    func buildReferredCodeFormScreen() -> some View {
        ReferredCodeFormScreen()
    }

    @ViewBuilder
    func buildVaultSelectionScreen(viewModel: VaultSelectedViewModel) -> some View {
        ReferralVaultSelectionScreen(viewModel: viewModel)
    }

    @ViewBuilder
    func buildTransactionFlowScreen(viewModel: VaultSelectedViewModel, thornameDetails: THORName?, currentBlockheight: UInt64) -> some View {
        ReferralTransactionFlowScreen(viewModel: viewModel, thornameDetails: thornameDetails, currentBlockHeight: currentBlockheight)
    }
}
