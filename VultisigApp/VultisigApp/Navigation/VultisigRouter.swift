//
//  VultisigRouter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

import SwiftUI

final class VultisigRouter: ObservableObject {
    @Published var navigationRouter: NavigationRouter
    let sendRouter: SendRouter

    init(navigationRouter: NavigationRouter) {
        self.navigationRouter = navigationRouter
        self.sendRouter = SendRouter(navigationRouter: navigationRouter)
    }
}
