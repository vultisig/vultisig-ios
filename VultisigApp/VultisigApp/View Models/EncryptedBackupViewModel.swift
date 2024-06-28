//
//  EncryptedBackupViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-13.
//

import Foundation
import CryptoKit
import SwiftData
import OSLog

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

class EncryptedBackupViewModel: ObservableObject {
    @Published var showVaultExporter = false
    @Published var showVaultImporter = false
    @Published var encryptedFileURL: URL? = nil
    @Published var decryptedContent: String? = nil
    @Published var encryptionPassword: String = ""
    @Published var decryptionPassword: String = ""
    
    @Published var isLinkActive: Bool = false
    @Published var showAlert: Bool = false
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""
    @Published var isFileUploaded = false
    @Published var importedFileName: String? = nil
    @Published var selectedVault: Vault? = nil
    
    private let logger = Logger(subsystem: "import-wallet", category: "communication")
    
    enum VultisigDocumentError : Error{
        case customError(String)
    }
    
    func resetData() {
        showVaultExporter = false
        showVaultImporter = false
        isFileUploaded = false
        importedFileName = nil
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
    
    // Import
    func importFile(from url: URL) {
        let success = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        
        guard success else {
            alertMessage = "Permission denied for accessing the file."
            showAlert = true
            return
        }
        do {
            let data = try Data(contentsOf: url)
            
            if let decryptedString = decryptOrReadData(data: data, password: "") {
                decryptedContent = decryptedString
                isFileUploaded = true
            } else {
                promptForPasswordAndImport(from: url)
            }
        } catch {
            print("Error reading file: \(error.localizedDescription)")
        }
    }
    
    func promptForPasswordAndImport(from url: URL) {
#if os(iOS)
        let alert = UIAlertController(title: NSLocalizedString("enterPassword", comment: ""), message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.isSecureTextEntry = true
            textField.placeholder = NSLocalizedString("password", comment: "").capitalized
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
#elseif os(macOS)
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("enterPassword", comment: "")
        alert.informativeText = ""
        alert.alertStyle = .informational
        
        let textField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.placeholderString = NSLocalizedString("password", comment: "").capitalized
        alert.accessoryView = textField
        
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        guard let mainWindow = NSApplication.shared.mainWindow else {
                // If there's no main window, show the alert as a modal dialog
            let alertWindow = alert.window
            let screenFrame = NSScreen.main?.frame ?? NSRect.zero
            let alertFrame = alertWindow.frame
            let centerX = screenFrame.midX - alertFrame.width / 2
            let centerY = screenFrame.midY - alertFrame.height / 2
            alertWindow.setFrameOrigin(NSPoint(x: centerX, y: centerY))
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let password = textField.stringValue
                self.decryptionPassword = password
                self.importFileWithPassword(from: url, password: password)
            }
            return
        }

        // Show the alert as a sheet attached to the main window
        alert.beginSheetModal(for: mainWindow) { response in
            if response == .alertFirstButtonReturn {
                let password = textField.stringValue
                self.decryptionPassword = password
                self.importFileWithPassword(from: url, password: password)
            }
        }
#endif
    }
    
    func importFileWithPassword(from url: URL, password: String) {
        let success = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        
        guard success else {
            alertMessage = "Permission denied for accessing the file."
            showAlert = true
            return
        }
        do {
            let data = try Data(contentsOf: url)
            if let decryptedData = decrypt(data: data, password: password),
               let decryptedString = String(data: decryptedData, encoding: .utf8) {
                decryptedContent = decryptedString
                isFileUploaded = true
            } else {
                decryptedContent = ""
                isFileUploaded = false
                importedFileName = nil
                alertTitle = "incorrectPassword"
                alertMessage = "backupDecryptionFailed"
                showAlert = true
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
            alertTitle = "error"
            alertMessage = "invalidVaultData"
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
                alertTitle = "error"
                alertMessage = "vaultAlreadyExists"
                showAlert = true
                isLinkActive = false
                return
            }
            VaultDefaultCoinService(context: modelContext)
                .setDefaultCoinsOnce(vault: backupVault.vault)
            modelContext.insert(backupVault.vault)
            selectedVault = backupVault.vault
            isLinkActive = true
        }  catch {
            print("failed to import with new format , fallback to the old format instead. \(error.localizedDescription)")
            // fallback
            do{
                let vault = try decoder.decode(Vault.self,
                                               from: vaultData)
                
                if !isVaultUnique(backupVault: vault,vaults:vaults){
                    alertTitle = "error"
                    alertMessage = "vaultAlreadyExists"
                    showAlert = true
                    isLinkActive = false
                    return
                }
                VaultDefaultCoinService(context: modelContext)
                    .setDefaultCoinsOnce(vault: vault)
                modelContext.insert(vault)
                selectedVault = vault
                isLinkActive = true
            } catch {
                logger.error("fail to restore vault: \(error.localizedDescription)")
                alertTitle = "vaultRestoreFailed"
                alertMessage = error.localizedDescription
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
