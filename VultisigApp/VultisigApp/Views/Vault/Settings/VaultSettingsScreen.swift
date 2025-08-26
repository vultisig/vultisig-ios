//
//  VaultSettingsScreen.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-12.
//

import SwiftUI
import SwiftData

struct VaultSettingsScreen: View {
    let vault: Vault
    
    @Query var vaults: [Vault]
    @Query var folders: [Folder]
    
    @Environment(\.dismiss) var dismiss
    
    @State var devicesInfo: [DeviceInfo] = []
    @State var showUpgradeYourVaultSheet = false
    @State var upgradeYourVaultLinkActive = false
    
    var body: some View {
        Screen(title: "vaultSettings".localized) {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    SettingsSectionView(title: "vaultManagement".localized) {
                        vaultDetails
                        editVault
                    }
                    
                    SettingsSectionView(title: "security".localized) {
                        if vault.isFastVault {
                            biometrySelectionCell
                        }
                        backupVault
                    }
                    
                    SettingsSectionView(title: "other".localized) {
                        VStack(spacing: .zero) {
                            if vault.libType == nil || vault.libType == .GG20 {
                                migrateVault
                            }
                            advancedSettings
                        }
                    }
                    
                    SettingsSectionContainerView {
                        VStack(spacing: .zero) {
                            deleteVault
                        }
                    }
                }
            }
        }
        .onLoad {
            setData()
        }
        .navigationDestination(isPresented: $upgradeYourVaultLinkActive) {
            if vault.isFastVault {
                VaultShareBackupsView(vault: vault)
            } else {
                AllDevicesUpgradeView(vault: vault)
            }
        }
        .sheet(isPresented: $showUpgradeYourVaultSheet) {
            UpgradeYourVaultView(
                showSheet: $showUpgradeYourVaultSheet,
                navigationLinkActive: $upgradeYourVaultLinkActive
            )
        }
    }
    
    var vaultDetails: some View {
        NavigationLink {
            VaultPairDetailView(vault: vault, devicesInfo: devicesInfo)
        } label: {
            SettingsOptionView(icon: "circle-info", title: "vaultDetailsTitle".localized, subtitle: "vaultDetailsDescription".localized)
        }
    }
    
    var backupVault: some View {
        NavigationLink {
            PasswordBackupOptionsView(tssType: .Keygen, vault: vault)
        } label: {
            SettingsOptionView(
                icon: "hard-drive-upload",
                title: "backupVaultShare".localized,
                subtitle: "backupVaultShareDescription".localized,
                showSeparator: false
            )
        }
    }
    
    var editVault: some View {
        NavigationLink {
            RenameVaultView(vaults: vaults, folders: folders, vault: vault)
        } label: {
            SettingsOptionView(
                icon: "pencil",
                title: "rename".localized,
                subtitle: "renameVault".localized,
                showSeparator: false
            )
        }
    }
    
    var deleteVault: some View {
        NavigationLink {
            VaultDeletionConfirmView(vault: vault, devicesInfo: devicesInfo)
        } label: {
            SettingsOptionView(
                icon: "trash",
                title: "delete".localized,
                subtitle: "deleteVault".localized,
                type: .alert,
                showSeparator: false
            )
        }
        
    }
    
    var biometrySelectionCell: some View {
        NavigationLink {
            SettingsBiometryView(vault: vault)
        } label: {
            SettingsOptionView(icon: "secure", title: "settingsBiometricsTitle".localized, subtitle: "settingsBiometricsSubtitle".localized)
        }
    }
    
    var migrateVault: some View {
        SettingsOptionView(icon: "arrow-up-from-dot", title: "migrate".localized, subtitle: "migrateVault".localized)
            .onTapGesture {
                showUpgradeYourVaultSheet = true
            }
    }
    
    var advancedSettings: some View {
        NavigationLink {
            VaultAdvancedSettingsScreen(vault: vault)
        } label: {
            SettingsOptionView(
                icon: "folder-key",
                title: "advanced".localized,
                subtitle: "advancedDescription".localized,
                showSeparator: false
            )
        }
    }
    
    private func setData() {
        devicesInfo = vault.signers.enumerated().map { index, signer in
            DeviceInfo(Index: index, Signer: signer)
        }
    }
}

#Preview {
    VaultSettingsScreen(vault: Vault.example)
}
