//
//  RenameVaultView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-12.
//

import SwiftUI

struct RenameVaultView: View {
    let vaults: [Vault]
    let folders: [Folder]
    let vault: Vault
    
    @State var name = ""
    @State var showAlert: Bool = false
    @State var errorMessage: String = ""
    
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.router) var router
    
    var body: some View {
        Screen(title: "renameVaultTitle".localized) {
            VStack {
                CommonTextField(
                    text: $name,
                    placeholder: "typeHere".localized
                )
                .maxLength($name)
                Spacer()
                button
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text(NSLocalizedString("error", comment: "")),
                message: Text(errorMessage),
                dismissButton: .default(Text("ok"))
            )
        }
        .onLoad {
            setData()
        }
    }
    
    var button: some View {
        PrimaryButton(title: "save") {
            rename()
        }
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
        appViewModel.set(selectedVault: vault, restartNavigation: false)
        
        checkForFolder(oldName: oldName, newName: name)
        router.navigateBack()
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
    RenameVaultView(vaults:[], folders: [], vault: Vault.example)
        .environmentObject(AppViewModel())
}
