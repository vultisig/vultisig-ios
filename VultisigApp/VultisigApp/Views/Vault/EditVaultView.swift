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
    @Environment(\.dismiss) var dismiss

    var body: some View {
        exporter
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
            VaultPairDetailView(vault: vault)
        } label: {
            EditVaultCell(title: "vaultDetailsTitle", description: "vaultDetailsDescription", icon: "info")
        }
    }
    
    var backupVault: some View {
        NavigationLink {
            BackupPasswordSetupView(vault: vault)
        } label: {
            EditVaultCell(title: "backup", description: "backupVault", icon: "icloud.and.arrow.up")
        }
    }
    
    var editVault: some View {
        NavigationLink {
            RenameVaultView(vaults: vaults, vault: vault)
        } label: {
            EditVaultCell(title: "rename", description: "renameVault", icon: "square.and.pencil")
        }
    }
    
    var deleteVault: some View {
        NavigationLink {
            VaultDeletionConfirmView(vault: vault, vaults: vaults)
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
            EditVaultCell(title: "Biometrics for Fast Sign", description: "Enable Biometrics for Fast Sign", icon: "person.badge.key")
        }
    }
}

#Preview {
    EditVaultView(vault: Vault.example)
}
