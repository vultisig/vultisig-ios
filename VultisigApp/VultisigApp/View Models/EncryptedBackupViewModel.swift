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
import VultisigCommonData
import UniformTypeIdentifiers

@MainActor
class EncryptedBackupViewModel: ObservableObject {
    @Published var showVaultExporter = false
    @Published var showVaultImporter = false
    @Published var encryptedFileURLWithPassowrd: URL? = nil
    @Published var encryptedFileURLWithoutPassowrd: URL? = nil
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
        encryptedFileURLWithPassowrd = nil
        encryptedFileURLWithoutPassowrd = nil
        decryptedContent = ""
        encryptionPassword = ""
        decryptionPassword = ""
    }
    
    // Export
    func exportFile(_ vault: Vault) {
        do {
            var vaultContainer = VSVaultContainer()
            vaultContainer.version = 1 // current version 1
            let vsVault = vault.mapToProtobuff()
            let data = try vsVault.serializedData()
            
            if encryptionPassword.isEmpty {
                vaultContainer.isEncrypted = false
                vaultContainer.vault = data.base64EncodedString()
            } else if let encryptedData = encrypt(data: data, password: encryptionPassword) {
                vaultContainer.isEncrypted = true
                vaultContainer.vault = encryptedData.base64EncodedString()
            } else {
                print("Error encrypting data")
                return
            }
            let dataToSave = try vaultContainer.serializedData().base64EncodedData()
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(vault.getExportName())
            
            do {
                try dataToSave.write(to: tempURL)
                encryptedFileURLWithPassowrd = tempURL
                encryptedFileURLWithoutPassowrd = tempURL
                print(tempURL.absoluteString)
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
            // read the file content
            if isBakFile() {
                try importBakFile(data: data)
                return
            }
            
            if let decryptedString = decryptOrReadData(data: data, password: "") {
                decryptedContent = decryptedString
                isFileUploaded = true
            } else {
                promptForPasswordAndImport(from: data)
            }
        } catch {
            print("Error reading file: \(error.localizedDescription)")
        }
    }
    
    func isBakFile() -> Bool {
        return self.importedFileName?.hasSuffix(".bak") ?? false
    }
    
    func importBakFile(data: Data) throws {
        guard let vsVaultContainer = Data(base64Encoded: data) else {
            throw ProtoMappableError.base64EncodedDataNotFound
        }
        let vaultContainer = try VSVaultContainer(serializedData: vsVaultContainer)
        guard let vaultData = Data(base64Encoded: vaultContainer.vault) else {
            throw ProtoMappableError.base64EncodedDataNotFound
        }
        if vaultContainer.isEncrypted {
            promptForPasswordAndImport(from: vaultData)
        } else {
            decryptedContent = vaultData.hexString
            isFileUploaded = true
        }
    }
    
    func importFileWithPassword(from data: Data, password: String) {
        if let decryptedData = decrypt(data: data, password: password) {
            if isBakFile() {
                decryptedContent = decryptedData.hexString
            } else if let decryptedString = String(data: decryptedData, encoding: .utf8) {
                decryptedContent = decryptedString
            }
            isFileUploaded = true
        } else {
            decryptedContent = ""
            isFileUploaded = false
            importedFileName = nil
            alertTitle = "incorrectPassword"
            alertMessage = "backupDecryptionFailed"
            showAlert = true
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
    
    func restoreVaultBak(modelContext: ModelContext,vaults: [Vault], vaultData: Data, defaultChains: [CoinMeta]) {
        do{
            let vsVault = try VSVault(serializedData: vaultData)
            let vault = try Vault(proto: vsVault)
            if !isVaultUnique(backupVault: vault,vaults:vaults){
                alertTitle = "error"
                alertMessage = "vaultAlreadyExists"
                showAlert = true
                isLinkActive = false
                return
            }
            VaultDefaultCoinService(context: modelContext)
                .setDefaultCoinsOnce(vault: vault, defaultChains: defaultChains)
            modelContext.insert(vault)
            selectedVault = vault
            isLinkActive = true
        }
        catch {
            logger.error("fail to restore vault: \(error.localizedDescription)")
            alertTitle = "vaultRestoreFailed"
            alertMessage = error.localizedDescription
            showAlert = true
            isLinkActive = false
        }
    }
    
    func restoreVault(modelContext: ModelContext, vaults: [Vault], defaultChains: [CoinMeta]) {
        guard let vaultText = decryptedContent, let vaultData = Data(hexString: vaultText) else {
            alertTitle = "error"
            alertMessage = "invalidVaultData"
            showAlert = true
            isLinkActive = false
            return
        }
        if isBakFile() {
            restoreVaultBak(modelContext: modelContext, vaults: vaults, vaultData: vaultData, defaultChains: defaultChains)
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
                .setDefaultCoinsOnce(vault: backupVault.vault, defaultChains: defaultChains)
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
                    .setDefaultCoinsOnce(vault: vault, defaultChains: defaultChains)
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
    
    private func isValidFormat(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        
        if fileExtension == "dat" || fileExtension == "bak"{
            return true
        } else {
            return false
        }
    }
    
    private func showInvalidFormatAlert() {
        alertTitle = "invalidFileFormat"
        alertMessage = "invalidFileFormatMessage"
        showAlert = true
    }
    
    func handleFileImporter(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                guard isValidFormat(url) else {
                    showInvalidFormatAlert()
                    return
                }
                
                importedFileName = url.lastPathComponent
                importFile(from: url)
            }
        case .failure(let error):
            print("Error importing file: \(error.localizedDescription)")
        }
    }
    
    func handleOnDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.data.identifier) }) else {
            print("Invalid file type.")
            return false
        }

        provider.loadInPlaceFileRepresentation(forTypeIdentifier: UTType.data.identifier) { url, success, error in
            guard let url = url else {
                print(error?.localizedDescription ?? "Failed to load file.")
                return
            }
            
            DispatchQueue.main.async {
                guard self.isValidFormat(url) else {
                    self.showInvalidFormatAlert()
                    return
                }
                
                self.importedFileName = url.lastPathComponent
                self.importFile(from: url)
            }
        }

        return true
    }
}
