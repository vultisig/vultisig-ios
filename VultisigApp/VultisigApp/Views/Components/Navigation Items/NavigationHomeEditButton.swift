//
//  NavigationHomeEditButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-17.
//

import SwiftUI

struct NavigationHomeEditButton: View {
    let vault: Vault?
    let showVaultsList: Bool
    @Binding var isEditingVaults: Bool
    @Binding var isEditingFolders: Bool
    @Binding var showFolderDetails: Bool
    
    var tint: Color = Color.neutral0
    
    @EnvironmentObject var viewModel: VaultDetailViewModel
    
    var body: some View {
        ZStack {
            if showFolderDetails {
                folderHomeEditButton
            } else {
                vaultHomeEditButton
            }
        }
    }
    
    var folderHomeEditButton: some View {
        ZStack {
            if showVaultsList {
                foldersListEditButton
            } else {
                vaultDetailQRCodeButton
            }
        }
    }
    
    var vaultHomeEditButton: some View {
        ZStack {
            if showVaultsList {
                vaultsListEditButton
            } else {
                vaultDetailQRCodeButton
            }
        }
    }
    
    var vaultsListEditButton: some View {
        Button {
            withAnimation(.easeInOut) {
                isEditingVaults.toggle()
            }
        } label: {
            if isEditingVaults {
                doneButton
            } else {
                editButton
            }
        }
    }
    
    var foldersListEditButton: some View {
        Button {
            withAnimation(.easeInOut) {
                isEditingFolders.toggle()
            }
        } label: {
            if isEditingFolders {
                doneButton
            } else {
                editButton
            }
        }
    }
    
    var vaultDetailQRCodeButton: some View {
        NavigationLink {
            if let vault {
                VaultDetailQRCodeView(vault: vault)
            }
        } label: {
            NavigationQRCodeButton()
        }
    }
    
    var editButton: some View {
        NavigationEditButton()
    }
    
    var doneButton: some View {
        Text(NSLocalizedString("done", comment: ""))
            .foregroundColor(tint)
            .font(.body18MenloBold)
    }
}

#Preview {
    ZStack {
        Background()
        VStack {
            NavigationHomeEditButton(
                vault: Vault.example,
                showVaultsList: true,
                isEditingVaults: .constant(true), 
                isEditingFolders: .constant(true),
                showFolderDetails: .constant(true)
            )
            
            NavigationHomeEditButton(
                vault: Vault.example,
                showVaultsList: true,
                isEditingVaults: .constant(false),
                isEditingFolders: .constant(true),
                showFolderDetails: .constant(true)
            )
        }
        .environmentObject(VaultDetailViewModel())
        .environmentObject(CoinSelectionViewModel())
    }
}
