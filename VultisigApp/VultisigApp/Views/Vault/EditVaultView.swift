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
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        exporter
    }
    
    var base: some View {
        ZStack {
            Background()
            view
        }
    }
    
    var navigation: some View {
        base
            .navigationBarBackButtonHidden(true)
            .navigationTitle(NSLocalizedString("editVault", comment: "Edit Vault View title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationBackButton()
                }
            }
    }
    
    var alert: some View {
        navigation
    }
    
    var exporter: some View {
        alert
    }
    
    var view: some View {
        ScrollView {
            VStack(spacing: 16) {
                deviceName
                vaultDetails
                backupVault
                editVault
                reshareVault
                deleteVault
            }
        }
    }
    
    var deviceName: some View {
        Text(vault.localPartyID)
            .padding(.top, 30)
            .font(.body16MenloBold)
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
            EditVaultCell(title: "backup", description: "backupVault", icon: "arrow.down.circle.fill")
        }
    }
    
    var editVault: some View {
        NavigationLink {
            RenameVaultView(vault: vault)
        } label: {
            EditVaultCell(title: "rename", description: "renameVault", icon: "square.and.pencil")
        }
    }
    
    var deleteVault: some View {
        NavigationLink {
            VaultDeletionConfirmView(vault: vault)
        } label: {
            EditVaultCell(title: "delete", description: "deleteVault", icon: "trash.fill", isDestructive: true)
        }

    }
    
    var reshareVault: some View {
        NavigationLink {
            SetupVaultView(tssType: .Reshare, vault: vault)
        } label: {
            EditVaultCell(title: "reshare", description: "reshareVault", icon: "square.and.arrow.up.fill")
        }
    }
}

#Preview {
    EditVaultView(vault: Vault.example)
}
