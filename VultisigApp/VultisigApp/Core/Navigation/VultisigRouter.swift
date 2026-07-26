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
    let swapRouter: SwapRouter
    let keygenRouter: KeygenRouter
    let vaultRouter: VaultRouter
    let onboardingRouter: OnboardingRouter
    let referralRouter: ReferralRouter
    let functionCallRouter: FunctionCallRouter
    let settingsRouter: SettingsRouter
    let homeRouter: HomeRouter
    let yieldRouter: YieldRouter
    let tronRouter: TronRouter
    let transactionHistoryRouter: TransactionHistoryRouter
    let qbtcClaimRouter: QBTCClaimRouter
    let signingRouter: SigningRouter

    init(navigationRouter: NavigationRouter) {
        self.navigationRouter = navigationRouter
        self.sendRouter = SendRouter()
        self.swapRouter = SwapRouter()
        self.keygenRouter = KeygenRouter()
        self.vaultRouter = VaultRouter()
        self.onboardingRouter = OnboardingRouter()
        self.referralRouter = ReferralRouter()
        self.functionCallRouter = FunctionCallRouter()
        self.settingsRouter = SettingsRouter()
        self.homeRouter = HomeRouter()
        self.yieldRouter = YieldRouter()
        self.tronRouter = TronRouter()
        self.transactionHistoryRouter = TransactionHistoryRouter()
        self.qbtcClaimRouter = QBTCClaimRouter()
        self.signingRouter = SigningRouter()
    }
}
