//
//  VaultRouter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

import SwiftUI

struct VaultRouter {
    private let navigationRouter: NavigationRouter
    private let viewBuilder = VaultRouteBuilder()

    init(navigationRouter: NavigationRouter) {
        self.navigationRouter = navigationRouter
    }

    @ViewBuilder
    func build(_ route: VaultRoute) -> some View {
        switch route {
        case .upgradeVault(let vault, let isFastVault):
            viewBuilder.buildUpgradeVaultScreen(vault: vault, isFastVault: isFastVault)
        case .serverBackup(let vault):
            viewBuilder.buildServerBackupScreen(vault: vault)
        case .backupPasswordOptions(let tssType, let backupType, let isNewVault):
            viewBuilder.buildBackupPasswordOptionsScreen(
                tssType: tssType,
                backupType: backupType,
                isNewVault: isNewVault
            )
        case .backupSelection(let vault):
            viewBuilder.buildBackupSelectionScreen(vault: vault)
        case .backupPasswordScreen(let tssType, let backupType, let isNewVault):
            viewBuilder.buildBackupPasswordScreen(
                tssType: tssType,
                backupType: backupType,
                isNewVault: isNewVault
            )
        case .backupSuccess(let tssType, let vault):
            viewBuilder.buildBackupSuccessScreen(tssType: tssType, vault: vault)
        case .createVault(let showBackButton):
            viewBuilder.buildCreateVaultScreen(showBackButton: showBackButton)
        case .home(let vault, let showVaultsList, let shouldJoinKeygen):
            viewBuilder.buildHomeScreen(
                vault: vault,
                showVaultsList: showVaultsList,
                shouldJoinKeygen: shouldJoinKeygen
            )
        }
    }
}
