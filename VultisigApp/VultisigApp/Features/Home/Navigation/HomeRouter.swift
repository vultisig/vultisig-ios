//
//  HomeRouter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 18/12/2025.
//

import SwiftUI

struct HomeRouter {
    private let navigationRouter: NavigationRouter
    private let viewBuilder = HomeRouteBuilder()
    
    init(navigationRouter: NavigationRouter) {
        self.navigationRouter = navigationRouter
    }
    
    func navigate(to route: HomeRoute) {
        navigationRouter.navigate(to: route)
    }
    
    @ViewBuilder
    func build(_ route: HomeRoute) -> some View {
        switch route {
        case .home(let showingVaultSelector):
            viewBuilder.buildHome(showingVaultSelector: showingVaultSelector)
        }
    }
}
