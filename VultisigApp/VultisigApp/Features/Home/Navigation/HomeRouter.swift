//
//  HomeRouter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 18/12/2025.
//

import SwiftUI

struct HomeRouter {
    private let viewBuilder = HomeRouteBuilder()

    @MainActor
    @ViewBuilder
    func build(_ route: HomeRoute) -> some View {
        switch route {
        case .home(let showingVaultSelector):
            viewBuilder.buildHome(showingVaultSelector: showingVaultSelector)
        case .vaultAction(let action, let vault):
            viewBuilder.buildActionRoute(action: action, vault: vault)
        }
    }
}
