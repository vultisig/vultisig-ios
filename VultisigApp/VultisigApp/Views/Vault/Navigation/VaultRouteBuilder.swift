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
        BackupVaultSuccessView(tssType: tssType, vault: vault)
    }

    @ViewBuilder
    func buildCreateVaultScreen(showBackButton: Bool) -> some View {
        CreateVaultView(showBackButton: showBackButton)
    }

    @ViewBuilder
    func buildHomeScreen(
        vault: Vault,
        showVaultsList: Bool,
        shouldJoinKeygen: Bool
    ) -> some View {
        HomeView(
            selectedVault: vault,
            showVaultsList: showVaultsList,
            shouldJoinKeygen: shouldJoinKeygen
        )
    }
}
