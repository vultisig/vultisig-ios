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
        Screen {
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
        .screenTitle("renameVaultTitle".localized)
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
        .disabled(trimmedName.isEmpty)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func setData() {
        name = vault.name
    }

    private func rename() {
        let oldName = vault.name
        let newName = trimmedName

        // Keeping the current name is always a no-op, even if legacy data
        // contains a case-insensitive duplicate of it
        guard newName != oldName else {
            router.navigateBack()
            return
        }

        // Same rules as vault creation: non-empty and not taken by another vault
        let otherVaultNames = vaults
            .filter { $0.pubKeyECDSA != vault.pubKeyECDSA && $0.pubKeyEdDSA != vault.pubKeyEdDSA }
            .map(\.name)

        do {
            try VaultNameValidator(existingNames: otherVaultNames).validate(value: newName)
        } catch {
            errorMessage = error.localizedDescription
            showAlert = true
            return
        }

        vault.name = newName
        appViewModel.set(selectedVault: vault, restartNavigation: false)

        checkForFolder(oldName: oldName, newName: newName)
        router.navigateBack()
    }

    private func checkForFolder(oldName: String, newName: String) {
        for folder in folders where folder.containedVaultNames.contains(oldName) {
            folder.containedVaultNames.append(newName)
        }
    }
}

#Preview {
    RenameVaultView(vaults: [], folders: [], vault: Vault.example)
        .environmentObject(AppViewModel())
}
