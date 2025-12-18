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
    func buildTransactionFlowScreen(isEdit: Bool) -> some View {
        ReferralTransactionFlowScreen(isEdit: isEdit)
    }
}
