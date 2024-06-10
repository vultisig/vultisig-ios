//
//  ImportVaultViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-13.
//

import Foundation
import SwiftData
import OSLog

class ImportVaultViewModel: ObservableObject {
    @Published var errorMessage: String = ""
    @Published var vaultText: String? = nil
    @Published var filename: String? = nil
    
    @Published var showAlert: Bool = false
    @Published var isLinkActive: Bool = false
    @Published var isFileUploaded: Bool = false
    @Published var vault: Vault? = nil
    
    private let logger = Logger(subsystem: "import-wallet", category: "communication")
    
    func readFile(for result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let selectedFileURL = urls.first else { return }
            
            print(selectedFileURL)
            isFileUploaded = true
            filename = selectedFileURL.lastPathComponent
            readContent(of: selectedFileURL)
        case .failure(let error):
            // Handle the error
            print("Error selecting file: \(error.localizedDescription)")
        }
    }
    
    func removeFile() {
        errorMessage = ""
        vaultText = nil
        filename = nil
        showAlert = false
        isFileUploaded = false
    }
    
    private func readContent(of url: URL) {
        let success = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        
        guard success else {
            errorMessage = "Permission denied for accessing the file."
            showAlert = true
            return
        }
        
        do {
            let fileContent = try String(contentsOf: url, encoding: .utf8)
            vaultText = fileContent
        } catch {
            errorMessage = "Failed to read file: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    func restoreVault(modelContext: ModelContext,vaults: [Vault]) {
        
        guard let vaultText = vaultText, let vaultData = Data(hexString: vaultText) else {
            errorMessage = "invalid vault data"
            showAlert = true
            isLinkActive = false
            return
        }
        
        let decoder = JSONDecoder()
        do {
            let backupVault = try decoder.decode(BackupVault.self,
                                                 from: vaultData)
            // if version get updated , then we can process the migration here
            if !isVaultUnique(backupVault: backupVault.vault,vaults:vaults){
                errorMessage = "Vault already exists"
                showAlert = true
                isLinkActive = false
                return
            }
            VaultDefaultCoinService(context: modelContext)
                .setDefaultCoinsOnce(vault: backupVault.vault)
            modelContext.insert(backupVault.vault)
            self.vault = backupVault.vault
            isLinkActive = true
        }  catch {
            print("failed to import with new format , fallback to the old format instead. \(error.localizedDescription)")
            // fallback
            do{
                let vault = try decoder.decode(Vault.self,
                                               from: vaultData)
                // if version get updated , then we can process the migration here
                if !isVaultUnique(backupVault: vault,vaults:vaults){
                    errorMessage = "Vault already exists"
                    showAlert = true
                    isLinkActive = false
                    return
                }
                VaultDefaultCoinService(context: modelContext)
                    .setDefaultCoinsOnce(vault: vault)
                modelContext.insert(vault)
                self.vault = vault
                isLinkActive = true
            } catch {
                logger.error("fail to restore vault: \(error.localizedDescription)")
                errorMessage = "fail to restore vault: \(error.localizedDescription)"
                showAlert = true
                isLinkActive = false
            }
        }
    }
    
    func isVaultUnique(backupVault: Vault,vaults: [Vault]) -> Bool {
        for vault in vaults{
            if vault.pubKeyECDSA == backupVault.pubKeyECDSA &&
                vault.pubKeyEdDSA == backupVault.pubKeyEdDSA {
                return false
            }
            
        }
        return true
    }
}
