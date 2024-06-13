//
//  EncryptedBackupViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-13.
//

import Foundation
import CryptoKit
import UIKit
import SwiftData
import OSLog

class EncryptedBackupViewModel: ObservableObject {
    @Published var showVaultExporter = false
    @Published var showVaultImporter = false
    @Published var encryptedFileURL: URL? = nil
    @Published var decryptedContent: String? = nil
    @Published var encryptionPassword: String = ""
    @Published var decryptionPassword: String = ""
    
    @Published var isLinkActive: Bool = false
    @Published var showAlert: Bool = false
    @Published var alertMessage: String = ""
    
    private let logger = Logger(subsystem: "import-wallet", category: "communication")
    
    enum VultisigDocumentError : Error{
        case customError(String)
    }
    
    func resetData() {
        showVaultExporter = false
        showVaultImporter = false
        encryptedFileURL = nil
        decryptedContent = ""
        encryptionPassword = ""
        decryptionPassword = ""
    }
    
    // Export
    
    func exportFile(_ vault: Vault) {
        do {
            let data = try JSONEncoder().encode(vault)
            guard let hexData = data.hexString.data(using: .utf8) else {
                throw VultisigDocumentError.customError("Could not convert data to hex")
            }
            
            let dataToSave: Data
            if encryptionPassword.isEmpty {
                dataToSave = hexData
            } else if let encryptedData = encrypt(data: hexData, password: encryptionPassword) {
                dataToSave = encryptedData
            } else {
                print("Error encrypting data")
                return
            }
            
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("file.dat")
            do {
                try dataToSave.write(to: tempURL)
                encryptedFileURL = tempURL
                showVaultExporter = true
            } catch {
                print("Error writing file: \(error.localizedDescription)")
            }
        } catch {
            print(error)
        }
    }
    
    private func encrypt(data: Data, password: String) -> Data? {
        let key = SymmetricKey(data: SHA256.hash(data: Data(password.utf8)))
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            return sealedBox.combined
        } catch {
            print("Error encrypting data: \(error.localizedDescription)")
            return nil
        }
    }
    
    func importFile(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            
            if let decryptedString = decryptOrReadData(data: data, password: "") {
                decryptedContent = decryptedString
            } else {
                promptForPasswordAndImport(from: url)
            }
        } catch {
            print("Error reading file: \(error.localizedDescription)")
        }
    }
    
    func promptForPasswordAndImport(from url: URL) {
        let alert = UIAlertController(title: "Enter Password", message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.isSecureTextEntry = true
            textField.placeholder = "Password"
        }
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            if let password = alert.textFields?.first?.text {
                self.decryptionPassword = password
                self.importFileWithPassword(from: url, password: password)
            }
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        if let rootViewController = UIApplication.shared.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true, completion: nil)
        }
    }
    
    func importFileWithPassword(from url: URL, password: String) {
        do {
            let data = try Data(contentsOf: url)
            if let decryptedData = decrypt(data: data, password: password),
               let decryptedString = String(data: decryptedData, encoding: .utf8) {
                decryptedContent = decryptedString
            } else {
                decryptedContent = "Failed to decrypt the content."
            }
        } catch {
            print("Error reading file: \(error.localizedDescription)")
        }
    }
    
    func decryptOrReadData(data: Data, password: String) -> String? {
        if password.isEmpty {
            return String(data: data, encoding: .utf8)
        } else {
            return decrypt(data: data, password: password).flatMap { String(data: $0, encoding: .utf8) }
        }
    }
    
    func decrypt(data: Data, password: String) -> Data? {
        let key = SymmetricKey(data: SHA256.hash(data: Data(password.utf8)))
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return decryptedData
        } catch {
            print("Error decrypting data: \(error.localizedDescription)")
            return nil
        }
    }
    
    func restoreVault(modelContext: ModelContext,vaults: [Vault]) {
        
        guard let vaultText = decryptedContent, let vaultData = Data(hexString: vaultText) else {
            alertMessage = "invalid vault data"
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
                alertMessage = "Vault already exists"
                showAlert = true
                isLinkActive = false
                return
            }
            VaultDefaultCoinService(context: modelContext)
                .setDefaultCoinsOnce(vault: backupVault.vault)
            modelContext.insert(backupVault.vault)
            isLinkActive = true
        }  catch {
            print("failed to import with new format , fallback to the old format instead. \(error.localizedDescription)")
            // fallback
            do{
                let vault = try decoder.decode(Vault.self,
                                               from: vaultData)
                // if version get updated , then we can process the migration here
                if !isVaultUnique(backupVault: vault,vaults:vaults){
                    alertMessage = "Vault already exists"
                    showAlert = true
                    isLinkActive = false
                    return
                }
                VaultDefaultCoinService(context: modelContext)
                    .setDefaultCoinsOnce(vault: vault)
                modelContext.insert(vault)
                isLinkActive = true
            } catch {
                logger.error("fail to restore vault: \(error.localizedDescription)")
                alertMessage = "fail to restore vault: \(error.localizedDescription)"
                showAlert = true
                isLinkActive = false
            }
        }
    }
    
    private func isVaultUnique(backupVault: Vault,vaults: [Vault]) -> Bool {
        for vault in vaults{
            if vault.pubKeyECDSA == backupVault.pubKeyECDSA &&
                vault.pubKeyEdDSA == backupVault.pubKeyEdDSA {
                return false
            }
            
        }
        return true
    }
}
