//
//  VaultRouteBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

import SwiftUI

struct VaultRouteBuilder {

    @ViewBuilder
    func buildUpgradeVaultScreen(vault: Vault, isFastVault: Bool) -> some View {
        if isFastVault {
            VaultShareBackupsView(vault: vault)
        } else {
            AllDevicesUpgradeView(vault: vault)
        }
    }

    @ViewBuilder
    func buildServerBackupScreen(vault: Vault) -> some View {
        VaultServerBackupScreen(vault: vault)
    }

    @ViewBuilder
    func buildBackupPasswordOptionsScreen(
        tssType: TssType,
        backupType: VaultBackupType,
        isNewVault: Bool
    ) -> some View {
        VaultBackupPasswordOptionsScreen(
            tssType: tssType,
            backupType: backupType,
            isNewVault: isNewVault
        )
    }

    @ViewBuilder
    func buildBackupSelectionScreen(vault: Vault) -> some View {
        VaultBackupSelectionScreen(selectedVault: vault)
    }

    @ViewBuilder
    func buildBackupPasswordScreen(
        tssType: TssType,
        backupType: VaultBackupType,
        isNewVault: Bool
    ) -> some View {
        VaultBackupPasswordScreen(
            tssType: tssType,
            backupType: backupType,
            isNewVault: isNewVault
        )
    }

    @ViewBuilder
    func buildBackupSuccessScreen(tssType: TssType, vault: Vault) -> some View {
        OnboardingSummaryScreen(
            kind: vault.libType == .KeyImport ? .keyImport : (vault.isFastVault ? .fast : .secure),
            vault: vault
        )
    }

    @ViewBuilder
    func buildCreateVaultScreen(showBackButton: Bool) -> some View {
        CreateVaultView(showBackButton: showBackButton)
    }

    @ViewBuilder
    func buildHomeScreen(showVaultsList: Bool) -> some View {
        HomeScreen(
            showingVaultSelector: showVaultsList
        )
    }

    @ViewBuilder
    func buildSwapScreen(fromCoin: Coin?, toCoin: Coin?, vault: Vault) -> some View {
        SwapCryptoView(fromCoin: fromCoin, toCoin: toCoin, vault: vault)
    }

    @ViewBuilder
    func buildAllDevicesUpgradeScreen(vault: Vault) -> some View {
        AllDevicesUpgradeView(vault: vault)
    }

    @ViewBuilder
    func buildVaultShareBackupsScreen(vault: Vault) -> some View {
        VaultShareBackupsView(vault: vault)
    }

    @ViewBuilder
    func buildReshareScreen(vault: Vault) -> some View {
        ReshareView(vault: vault)
    }

    @ViewBuilder
    func buildPasswordHintScreen(vault: Vault) -> some View {
        SettingsPasswordHintScreen(vault: vault, viewModel: SettingsBiometryViewModel())
    }

    @ViewBuilder
    func buildVaultDetailsScreen(vault: Vault, devicesInfo: [DeviceInfo]) -> some View {
        VaultPairDetailView(vault: vault, devicesInfo: devicesInfo)
    }

    @ViewBuilder
    func buildRenameVaultScreen(vault: Vault, vaults: [Vault], folders: [Folder]) -> some View {
        RenameVaultView(vaults: vaults, folders: folders, vault: vault)
    }

    @ViewBuilder
    func buildDeleteVaultScreen(vault: Vault, devicesInfo: [DeviceInfo]) -> some View {
        VaultDeletionConfirmView(vault: vault, devicesInfo: devicesInfo)
    }

    @ViewBuilder
    func buildAdvancedSettingsScreen(vault: Vault) -> some View {
        VaultAdvancedSettingsScreen(vault: vault)
    }

    @ViewBuilder
    func buildCustomMessageScreen(vault: Vault) -> some View {
        SettingsCustomMessageView(vault: vault)
    }

    @ViewBuilder
    func buildOnChainSecurityScreen() -> some View {
        OnChainSecurityScreen()
    }

    @ViewBuilder
    func buildChainDetailScreen(groupedChain: GroupedChain, vault: Vault) -> some View {
        ChainDetailScreenContainer(group: groupedChain, vault: vault)
    }

    @ViewBuilder
    func buildDefiChainDetailScreen(groupedChain: GroupedChain, vault: Vault) -> some View {
        DefiChainMainScreen(vault: vault, group: groupedChain)
    }
}
