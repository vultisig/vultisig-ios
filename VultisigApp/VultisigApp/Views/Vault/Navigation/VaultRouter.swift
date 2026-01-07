//
//  VaultRouter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

import SwiftUI

struct VaultRouter {
    private let viewBuilder = VaultRouteBuilder()

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
        case .swap(let fromCoin, let toCoin, let vault):
            viewBuilder.buildSwapScreen(fromCoin: fromCoin, toCoin: toCoin, vault: vault)
        case .allDevicesUpgrade(let vault):
            viewBuilder.buildAllDevicesUpgradeScreen(vault: vault)
        case .vaultShareBackups(let vault):
            viewBuilder.buildVaultShareBackupsScreen(vault: vault)
        case .reshare(let vault):
            viewBuilder.buildReshareScreen(vault: vault)
        case .passwordHint(let vault):
            viewBuilder.buildPasswordHintScreen(vault: vault)
        case .vaultDetails(let vault, let devicesInfo):
            viewBuilder.buildVaultDetailsScreen(vault: vault, devicesInfo: devicesInfo)
        case .renameVault(let vault, let vaults, let folders):
            viewBuilder.buildRenameVaultScreen(vault: vault, vaults: vaults, folders: folders)
        case .deleteVault(let vault, let devicesInfo):
            viewBuilder.buildDeleteVaultScreen(vault: vault, devicesInfo: devicesInfo)
        case .advancedSettings(let vault):
            viewBuilder.buildAdvancedSettingsScreen(vault: vault)
        case .customMessage(let vault):
            viewBuilder.buildCustomMessageScreen(vault: vault)
        case .onChainSecurity:
            viewBuilder.buildOnChainSecurityScreen()
        case .chainDetail(let groupedChain, let vault):
            viewBuilder.buildChainDetailScreen(groupedChain: groupedChain, vault: vault)
        case .defiChain(let groupedChain, let vault):
            viewBuilder.buildDefiChainDetailScreen(groupedChain: groupedChain, vault: vault)
        }
    }
}
