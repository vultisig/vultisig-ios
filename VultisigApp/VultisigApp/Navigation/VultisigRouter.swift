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
    let settingsRouter: SettingsRouter
    let homeRouter: HomeRouter
    let circleRouter: CircleRouter
    let tronRouter: TronRouter

    init(navigationRouter: NavigationRouter) {
        self.navigationRouter = navigationRouter
        self.sendRouter = SendRouter()
        self.keygenRouter = KeygenRouter()
        self.vaultRouter = VaultRouter()
        self.onboardingRouter = OnboardingRouter()
        self.referralRouter = ReferralRouter()
        self.functionCallRouter = FunctionCallRouter()
        self.settingsRouter = SettingsRouter()
        self.homeRouter = HomeRouter()
        self.circleRouter = CircleRouter()
        self.tronRouter = TronRouter()
    }
}
