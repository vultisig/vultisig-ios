//
//  HomeRouter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 18/12/2025.
//

import SwiftUI

struct HomeRouter {
    private let viewBuilder = HomeRouteBuilder()
    
    @ViewBuilder
    func build(_ route: HomeRoute) -> some View {
        switch route {
        case .home(let showingVaultSelector):
            viewBuilder.buildHome(showingVaultSelector: showingVaultSelector)
        case .vaultAction(let action, let sendTx, let vault):
            viewBuilder.buildActionRoute(action: action, sendTx: sendTx, vault: vault)
        }
    }
}
