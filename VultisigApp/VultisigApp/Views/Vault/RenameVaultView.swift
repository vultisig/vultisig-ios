//
//  RenameVaultView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-12.
//

import SwiftUI
import SwiftData

struct RenameVaultView: View {
    let vaults: [Vault]
    let vault: Vault
    
    @State var name = ""
    @Environment(\.dismiss) var dismiss
    @State var showAlert: Bool = false
    @State var errorMessage: String = ""
    
    @Query var folders: [Folder]
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var body: some View {
        content
            .onAppear {
                setData()
            }
    }
    
    var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("vaultName", comment: ""))
                .font(.body14MontserratMedium)
                .foregroundColor(.neutral0)
            
            textfield
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
    }
    
    var textfield: some View {
        TextField(NSLocalizedString("typeHere", comment: "").capitalized, text: $name)
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .submitLabel(.done)
            .padding(12)
            .background(Color.blue600)
            .cornerRadius(12)
            .borderlessTextFieldStyle()
            .maxLength($name)
    }
    
    var button: some View {
        Button {
            rename()
        } label: {
            FilledButton(title: "save")
        }
        .padding(40)
    }
    
    private func setData() {
        name = vault.name
    }
    
    private func rename() {
        // make sure the same vault name has not been occupied
        if vaults.contains(where: { $0.name == name && $0.pubKeyECDSA != vault.pubKeyECDSA && $0.pubKeyEdDSA != vault.pubKeyEdDSA}) {
            name = vault.name
            errorMessage = NSLocalizedString("vaultNameExists", comment: "").replacingOccurrences(of: "%s", with: name)
            showAlert = true
            return
        }
        
        let oldName = vault.name
        
        vault.name = name
        homeViewModel.selectedVault = vault
        homeViewModel.vaultName = name
        
        checkForFolder(oldName: oldName, newName: name)
        dismiss()
    }
    
    private func checkForFolder(oldName: String, newName: String) {
        for folder in folders {
            if folder.containedVaultNames.contains(oldName) {
                folder.containedVaultNames.append(newName)
            }
        }
    }
}

#Preview {
    RenameVaultView(vaults:[],vault: Vault.example)
        .environmentObject(HomeViewModel())
}
