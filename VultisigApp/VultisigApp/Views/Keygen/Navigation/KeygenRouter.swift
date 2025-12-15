//
//  KeygenRouter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

import SwiftUI

struct KeygenRouter {
    private let navigationRouter: NavigationRouter
    private let viewBuilder = KeygenRouteBuilder()

    init(navigationRouter: NavigationRouter) {
        self.navigationRouter = navigationRouter
    }

    @ViewBuilder
    func build(_ route: KeygenRoute) -> some View {
        switch route {
        case .fastBackupOverview(let tssType, let vault, let email):
            viewBuilder.buildFastBackupOverviewScreen(
                tssType: tssType,
                vault: vault,
                email: email
            )
        case .secureBackupOverview(let vault):
            viewBuilder.buildSecureBackupOverviewScreen(vault: vault)
        case .backupNow(let tssType, let backupType, let isNewVault):
            viewBuilder.buildBackupNowScreen(
                tssType: tssType,
                backupType: backupType,
                isNewVault: isNewVault
            )
        case .keyImportOverview(let vault, let email, let keyImportInput):
            viewBuilder.buildKeyImportOverviewScreen(
                vault: vault,
                email: email,
                keyImportInput: keyImportInput
            )
        case .peerDiscovery(let tssType, let vault, let selectedTab, let fastSignConfig, let keyImportInput):
            viewBuilder.buildPeerDiscoveryScreen(
                tssType: tssType,
                vault: vault,
                selectedTab: selectedTab,
                fastSignConfig: fastSignConfig,
                keyImportInput: keyImportInput
            )
        case .fastVaultSetHint(let tssType, let vault, let selectedTab, let fastVaultEmail, let fastVaultPassword, let fastVaultExist):
            viewBuilder.buildFastVaultSetHintScreen(
                tssType: tssType,
                vault: vault,
                selectedTab: selectedTab,
                fastVaultEmail: fastVaultEmail,
                fastVaultPassword: fastVaultPassword,
                fastVaultExist: fastVaultExist
            )
        case .fastVaultSetPassword(let tssType, let vault, let selectedTab, let fastVaultEmail, let fastVaultExist):
            viewBuilder.buildFastVaultSetPasswordScreen(
                tssType: tssType,
                vault: vault,
                selectedTab: selectedTab,
                fastVaultEmail: fastVaultEmail,
                fastVaultExist: fastVaultExist
            )
        case .newWalletName(let tssType, let selectedTab, let name):
            viewBuilder.buildNewWalletNameScreen(
                tssType: tssType,
                selectedTab: selectedTab,
                name: name
            )
        }
    }
}
