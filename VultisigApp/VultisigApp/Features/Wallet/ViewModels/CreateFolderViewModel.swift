//
//  CreateFolderViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-08.
//

import SwiftUI

class CreateFolderViewModel: ObservableObject {
    @Published var name = "" {
        didSet {
            folderNameError = nil
        }
    }
    @Published var selectedVaults: [Vault] = []
    @Published var vaultFolder: Folder? = nil

    @Published var folderNameError: String?

    private let logic = CreateFolderLogic()

    var saveButtonDisabled: Bool {
        name.isEmpty || selectedVaults.isEmpty
    }

    func runChecks(_ folders: [Folder]) -> Bool {
        let result = logic.validateFolder(name: name, selectedVaults: selectedVaults, folders: folders)
        folderNameError = result.errorMessage
        return result.isValid
    }

    func showErrorAlert() {
        folderNameError = "somethingWentWrongTryAgain".localized
    }

    func setupFolder(_ count: Int) {
        vaultFolder = logic.createFolder(name: name, selectedVaults: selectedVaults, order: count)
    }
}

// MARK: - CreateFolderLogic

struct CreateFolderLogic {

    struct ValidationResult {
        let isValid: Bool
        let errorMessage: String?
    }

    func validateFolder(name: String, selectedVaults: [Vault], folders: [Folder]) -> ValidationResult {
        if name.isEmpty {
            return ValidationResult(isValid: false, errorMessage: "enterValidFolderName".localized)
        }

        if selectedVaults.isEmpty {
            return ValidationResult(isValid: false, errorMessage: "selectAtleastOneVault".localized)
        }

        for folder in folders {
            if folder.folderName == name {
                return ValidationResult(isValid: false, errorMessage: "sameNameFolderDescription".localized)
            }
        }

        return ValidationResult(isValid: true, errorMessage: nil)
    }

    func createFolder(name: String, selectedVaults: [Vault], order: Int) -> Folder {
        return Folder(
            folderName: name,
            containedVaultNames: selectedVaults.map({ vault in
                vault.name
            }),
            order: order
        )
    }
}
