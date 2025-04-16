//
//  EditVaultView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-12.
//

import SwiftUI
import SwiftData

struct EditVaultView: View {
    let vault: Vault

    @Query var vaults: [Vault]
    @Query var folders: [Folder]
    
    @Environment(\.dismiss) var dismiss
    
    @State var devicesInfo: [DeviceInfo] = []
    @State var showUpgradeYourVaultSheet = false
    @State var upgradeYourVaultLinkActive = false

    var body: some View {
        exporter
            .onAppear {
                setData()
            }
            .navigationDestination(isPresented: $upgradeYourVaultLinkActive, destination: {
                if vault.isFastVault {
                    VaultShareBackupsView(vault: vault)
                } else {
                    AllDevicesUpgradeView(vault: vault)
                }
            })
            .sheet(isPresented: $showUpgradeYourVaultSheet) {
                UpgradeYourVaultView(
                    showSheet: $showUpgradeYourVaultSheet,
                    navigationLinkActive: $upgradeYourVaultLinkActive
                )
            }
    }
    
    var base: some View {
        ZStack {
            Background()
            main
        }
    }
    
    var alert: some View {
        navigation
    }
    
    var exporter: some View {
        alert
    }
    
    var deviceName: some View {
        Text(vault.localPartyID)
            .padding(.top, 30)
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
    }
    
    var vaultDetails: some View {
        NavigationLink {
            VaultPairDetailView(vault: vault, devicesInfo: devicesInfo)
        } label: {
            EditVaultCell(title: "vaultDetailsTitle", description: "vaultDetailsDescription", icon: "info")
        }
    }
    
    var backupVault: some View {
        NavigationLink {
            PasswordBackupOptionsView(vault: vault)
        } label: {
            EditVaultCell(title: "backup", description: "backupVault", icon: "icloud.and.arrow.up")
        }
    }

    var customMessage: some View {
        NavigationLink {
            SettingsCustomMessageView(vault: vault)
        } label: {
            EditVaultCell(title: "Sign", description: "Sign custom message", icon: "signature")
        }
    }

    var editVault: some View {
        NavigationLink {
            RenameVaultView(vaults: vaults, folders: folders, vault: vault)
        } label: {
            EditVaultCell(title: "rename", description: "renameVault", icon: "square.and.pencil")
        }
    }
    
    var deleteVault: some View {
        NavigationLink {
            VaultDeletionConfirmView(vault: vault, devicesInfo: devicesInfo, vaults: vaults)
        } label: {
            EditVaultCell(title: "delete", description: "deleteVault", icon: "trash", isDestructive: true)
        }
        
    }
    
    var reshareVault: some View {
        NavigationLink {
            ReshareView(vault: vault)
        } label: {
            EditVaultCell(title: "reshare", description: "reshareVault", icon: "tray.and.arrow.up")
        }
    }

    var biometrySelectionCell: some View {
        NavigationLink {
            SettingsBiometryView(vault: vault)
        } label: {
            EditVaultCell(title: "settingsBiometricsTitle", description: "settingsBiometricsSubtitle", icon: "person.badge.key")
        }
    }
    
    var migrateVault: some View {
        EditVaultCell(title: "migrate", description: "migrateVault", icon: "arrow.up.circle")
            .onTapGesture {
                showUpgradeYourVaultSheet = true
            }
    }
    
    private func setData() {
        devicesInfo = vault.signers.enumerated().map { index, signer in
            DeviceInfo(Index: index, Signer: signer)
        }
    }
}

#Preview {
    EditVaultView(vault: Vault.example)
}
