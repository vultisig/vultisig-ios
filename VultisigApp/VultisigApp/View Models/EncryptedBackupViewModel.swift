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
    
    @Published var showPopup: Bool = false
    @Published var isLinkActive: Bool = false
    @Published var showAlert: Bool = false
    @Published var alertTitle: String = ""
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
        showAlert = false
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
    
    func importDragDropFile(content: Data){
        do {
            if isBakFile() {
                try importBakFile(data: content)
                return
            }
            
            if let decryptedString = decryptOrReadData(data: content, password: "") {
                decryptedContent = decryptedString
                isFileUploaded = true
            } else {
                promptForPasswordAndImport(from: content)
            }
        } catch {
            print("Error reading file: \(error.localizedDescription)")
        }
    }
    
    // Import
    func importFile(from url: URL) {
        let _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        
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
        return self.importedFileName?.hasSuffix(".bak") ?? false || self.importedFileName?.hasSuffix(".vult") ?? false
    }
    
    func importBakFile(data: Data) throws {
        guard let vsVaultContainer = Data(base64Encoded: data) else {
            throw ProtoMappableError.base64EncodedDataNotFound
        }
        let vaultContainer = try VSVaultContainer(serializedBytes: vsVaultContainer)
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
            alertTitle = "incorrectPasswordTryAgain"
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
    
    func isDKLS(filename: String) -> Bool {
        do{
            let regex = try NSRegularExpression(pattern: "share\\d+of\\d+") // share2of3, share3of5
            let matches = regex.matches(in: filename, range: NSRange(filename.startIndex..., in: filename))
            return matches.count > 0
        } catch {
            print("Error checking if filename is a DKLS backup: \(error.localizedDescription)")
            return false
        }
    }
    
    func restoreVaultBak(modelContext: ModelContext,vaults: [Vault], vaultData: Data, defaultChains: [CoinMeta]) {
        do{
            let vsVault = try VSVault(serializedBytes: vaultData)
            let vault = try Vault(proto: vsVault)
            if !isVaultUnique(backupVault: vault,vaults:vaults){
                alertTitle = "vaultAlreadyExists"
                showAlert = true
                isLinkActive = false
                return
            }
            if isDKLS(filename: self.importedFileName ?? ""), vault.libType != LibType.GG20 {
                vault.libType = LibType.DKLS
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
            showAlert = true
            isLinkActive = false
        }
    }
    
    func restoreVault(modelContext: ModelContext, vaults: [Vault], defaultChains: [CoinMeta]) {
        guard let vaultText = decryptedContent, let vaultData = Data(hexString: vaultText) else {
            alertTitle = "invalidVaultData"
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
                alertTitle = "vaultAlreadyExists"
                showAlert = true
                isLinkActive = false
                return
            }
            VaultDefaultCoinService(context: modelContext)
                .setDefaultCoinsOnce(vault: backupVault.vault, defaultChains: defaultChains)
            modelContext.insert(backupVault.vault)
            selectedVault = backupVault.vault
            showAlert = false
            isLinkActive = true
        }  catch {
            print("failed to import with new format , fallback to the old format instead. \(error.localizedDescription)")
            
            // fallback
            do{
                let vault = try decoder.decode(Vault.self, from: vaultData)
                
                if !isVaultUnique(backupVault: vault,vaults:vaults){
                    alertTitle = "vaultAlreadyExists"
                    showAlert = true
                    isLinkActive = false
                    return
                }
                VaultDefaultCoinService(context: modelContext)
                    .setDefaultCoinsOnce(vault: vault, defaultChains: defaultChains)
                modelContext.insert(vault)
                selectedVault = vault
                showAlert = false
                isLinkActive = true
            } catch {
                logger.error("fail to restore vault: \(error.localizedDescription)")
                alertTitle = "vaultRestoreFailed"
                showAlert = true
                isLinkActive = false
            }
        }
    }
    
    private func isVaultUnique(backupVault: Vault,vaults: [Vault]) -> Bool {
        for vault in vaults {
            if vault.pubKeyECDSA == backupVault.pubKeyECDSA &&
                vault.pubKeyEdDSA == backupVault.pubKeyEdDSA {
                return false
            }
            
        }
        return true
    }
    
    private func isValidFormat(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        
        if fileExtension == "dat" || fileExtension == "bak" ||  fileExtension == "vult" {
            return true
        } else {
            return false
        }
    }
    
    private func showInvalidFormatAlert() {
        alertTitle = "unsupportedFileTypeError"
        showAlert = true
    }
    
    func handleFileImporter(_ result: Result<[URL], Error>) {
        resetData()
        
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
    
    func handleFileDocument(_ url: URL) {
        guard isValidFormat(url) else {
            showInvalidFormatAlert()
            return
        }
        
        importedFileName = url.lastPathComponent
        importFile(from: url)
    }
    
    func handleOnDrop(providers: [NSItemProvider]) async {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.data.identifier) }) else {
            print("Invalid file type.")
            return
        }
        do{
            let dragDropData = try await provider.loadItem(forTypeIdentifier: UTType.data.identifier)
            if let urlData = dragDropData as? NSURL {
                print("File Path as NSURL: \(urlData)")
                provider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data,err in
                    if let data {
                        let url = urlData as URL
                        DispatchQueue.main.async {
                            guard self.isValidFormat(url) else {
                                self.showInvalidFormatAlert()
                                return
                            }    
                            self.importedFileName = url.lastPathComponent
                            self.importDragDropFile(content: data)
                        }
                    }
                }
            }
        } catch {
            DispatchQueue.main.async{
                self.alertTitle = "failedToLoadFileData"
                self.showAlert = true
            }
            print("fail to process drag and drop file: \(error.localizedDescription)")
        }
    }
}
