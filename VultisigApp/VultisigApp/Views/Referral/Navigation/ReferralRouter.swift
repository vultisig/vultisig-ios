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
        case .referredCodeForm(let referredViewModel, let referralViewModel):
            viewBuilder.buildReferredCodeFormScreen(
                referredViewModel: referredViewModel,
                referralViewModel: referralViewModel
            )
        case .vaultSelection(let selectedVault):
            viewBuilder.buildVaultSelectionScreen(selectedVault: selectedVault)
        }
    }
}
