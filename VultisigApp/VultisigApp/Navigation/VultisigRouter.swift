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
    let keygenRouter: KeygenRouter
    let vaultRouter: VaultRouter
    let onboardingRouter: OnboardingRouter
    let referralRouter: ReferralRouter
    let functionCallRouter: FunctionCallRouter

    init(navigationRouter: NavigationRouter) {
        self.navigationRouter = navigationRouter
        self.sendRouter = SendRouter(navigationRouter: navigationRouter)
        self.keygenRouter = KeygenRouter(navigationRouter: navigationRouter)
        self.vaultRouter = VaultRouter(navigationRouter: navigationRouter)
        self.onboardingRouter = OnboardingRouter(navigationRouter: navigationRouter)
        self.referralRouter = ReferralRouter(navigationRouter: navigationRouter)
        self.functionCallRouter = FunctionCallRouter(navigationRouter: navigationRouter)
    }
}
