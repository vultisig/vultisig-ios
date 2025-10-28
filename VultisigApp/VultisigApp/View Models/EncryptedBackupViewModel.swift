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
    @Published var decryptedContent: String?
    @Published var encryptionPassword: String = ""
    @Published var decryptionPassword: String = ""
    
    @Published var showPopup: Bool = false
    @Published var isLinkActive: Bool = false
    @Published var showAlert: Bool = false
    @Published var alertTitle: String = ""
    @Published var isFileUploaded = false
    @Published var importedFileName: String?
    @Published var selectedVault: Vault?
    
    // New properties for multiple vault imports
    @Published var multipleVaultsToImport: [Vault] = []
    @Published var isMultipleVaultImport: Bool = false
    @Published var extractedFilesDirectory: URL?
    @Published var pendingEncryptedVaults: [(fileName: String, data: Data)] = []
    
    private let logger = Logger(subsystem: "import-wallet", category: "communication")
    private let keychain = DefaultKeychainService.shared
    
    enum VultisigDocumentError : Error{
        case customError(String)
    }
    
    func resetData() {
        showVaultExporter = false
        showVaultImporter = false
        isFileUploaded = false
        importedFileName = nil
        decryptedContent = ""
        decryptionPassword = ""
        showAlert = false
        cleanupExtractedFiles()
        multipleVaultsToImport = []
        isMultipleVaultImport = false
    }
    
    /// Cleanup extracted files from zip import
    private func cleanupExtractedFiles() {
        guard let extractionDir = extractedFilesDirectory else { return }
        try? FileManager.default.removeItem(at: extractionDir)
        extractedFilesDirectory = nil
    }
    
    func exportFileWithoutPassword(_ backupType: VaultBackupType) async -> FileExporterModel<EncryptedDataFile>? {
        return try? await createBackupFile(backupType, encryptionPassword: nil)
    }
    
    func exportFileWithVaultPassword(_ backupType: VaultBackupType) async -> FileExporterModel<EncryptedDataFile>? {
        guard let vaultPassword = keychain.getFastPassword(pubKeyECDSA: backupType.vault.pubKeyECDSA) else {
            debugPrint("Couldn't fetch password for vault")
            return nil
        }
        
        return try? await createBackupFile(backupType, encryptionPassword: vaultPassword)
    }
    
    func exportFileWithCustomPassword(_ backupType: VaultBackupType) async -> FileExporterModel<EncryptedDataFile>? {
        return try? await createBackupFile(backupType, encryptionPassword: encryptionPassword)
    }
    
    func createBackupFile(_ backupType: VaultBackupType, encryptionPassword: String?) async throws -> FileExporterModel<EncryptedDataFile>? {
        switch backupType {
        case .single(let vault):
            return try await createSingleBackupFile(vault: vault, encryptionPassword: encryptionPassword)
        case .multiple(let vaults, let selectedVault):
            return try await createMultipleBackupFile(vaults: vaults, selectedVault: selectedVault, encryptionPassword: encryptionPassword)
        }
    }
    
    func createMultipleBackupFile(vaults: [Vault], selectedVault: Vault, encryptionPassword: String?) async throws -> FileExporterModel<EncryptedDataFile>? {
        let timestamp = Int(Date().timeIntervalSince1970)
        let backupFolderName = "vultisig_backups_\(timestamp)"
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(backupFolderName)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        for vault in vaults {
            _ = try generateBackupFile(vault: vault, encryptionPassword: encryptionPassword, targetDirectory: tempDir)
        }
        
        let zipGenerator = ZipFileGenerator()
        let zipFileName = "\(backupFolderName).zip"
        let zipUrl = FileManager.default.temporaryDirectory.appendingPathComponent(zipFileName)
        
        _ = try zipGenerator.createZip(zipFinalURL: zipUrl, fromDirectory: tempDir)
        
        guard let zipFile = EncryptedDataFile(url: zipUrl) else {
            return nil
        }
        
        return FileExporterModel(
            url: zipUrl,
            name: zipFileName,
            file: zipFile
        )
    }
    
    func generateBackupFile(vault: Vault, encryptionPassword: String?, targetDirectory: URL? = nil) throws -> URL? {
        var vaultContainer = VSVaultContainer()
        vaultContainer.version = 1 // current version 1
        let vsVault = vault.mapToProtobuff()
        let data = try vsVault.serializedData()
        
        if let encryptionPassword {
            guard let encryptedData = encrypt(data: data, password: encryptionPassword) else {
                return nil
            }
            vaultContainer.isEncrypted = true
            vaultContainer.vault = encryptedData.base64EncodedString()
        } else {
            vaultContainer.isEncrypted = false
            vaultContainer.vault = data.base64EncodedString()
        }
        
        let fileName = vault.getExportName()
        let dataToSave = try vaultContainer.serializedData().base64EncodedData()
        let directory = targetDirectory ?? FileManager.default.temporaryDirectory
        let fileURL = directory.appendingPathComponent(fileName)
        try dataToSave.write(to: fileURL)
        
        return fileURL
    }

    func createSingleBackupFile(vault: Vault, encryptionPassword: String?) async throws -> FileExporterModel<EncryptedDataFile>? {
        let tempURL = try generateBackupFile(vault: vault, encryptionPassword: encryptionPassword)
        guard let tempURL, let file = EncryptedDataFile(url: tempURL) else {
            return nil
        }
        
        let fileName = vault.getExportName()
        return FileExporterModel(
            url: tempURL,
            name: fileName,
            file: file
        )
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
            
            // Check if it's a zip file with multiple vaults
            if isZipFile() {
                try importMultipleVaultsFromZip(zipURL: url)
                return
            }
            
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
    
    func isZipFile() -> Bool {
        return self.importedFileName?.hasSuffix(".zip") ?? false
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
    
    /// Import multiple vaults from a zip file
    func importMultipleVaultsFromZip(zipURL: URL) throws {
        print("🔍 DEBUG: Starting import from ZIP: \(zipURL.path)")
        var importedVaults: [Vault] = []
        
        // Create a temporary directory for extraction
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("VultisigZipExtract_\(UUID().uuidString)")
        
        do {
            // Create temp directory
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            self.extractedFilesDirectory = tempDir
            print("📦 DEBUG: Created temp directory: \(tempDir.path)")
            
            // Try to extract using FileManager's built-in unzip (iOS 15+)
            var extractedSuccessfully = false
            
            // Try to extract on all platforms using ZIPFoundation via FileManagerExtension
            do {
                // Create a subdirectory for extraction
                let extractDir = tempDir.appendingPathComponent("extracted")
                try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true, attributes: nil)
                
                try fileManager.unzipItem(at: zipURL, to: extractDir)
                print("📦 DEBUG: Successfully extracted to: \(extractDir.path)")
                
                self.extractedFilesDirectory = extractDir
                extractedSuccessfully = true
                
                let vaultFiles = findVaultFilesRecursively(in: extractDir)
                print("📁 DEBUG: Found \(vaultFiles.count) vault files")
                for (index, file) in vaultFiles.enumerated() {
                    print("  File \(index + 1): \(file.lastPathComponent)")
                }
                
                importedVaults = processVaultFiles(vaultFiles)
                print("✅ DEBUG: Processed \(importedVaults.count) vaults successfully")
            } catch {
                print("⚠️ DEBUG: unzipItem failed: \(error)")
                extractedSuccessfully = false
            }
            
            // Fallback: Use NSFileCoordinator
            if !extractedSuccessfully {
                var coordinatorError: NSError?
                let coordinator = NSFileCoordinator(filePresenter: nil)
                
                coordinator.coordinate(readingItemAt: zipURL, options: [.forUploading], error: &coordinatorError) { (extractedURL) in
                    print("📦 DEBUG: NSFileCoordinator result: \(extractedURL.path)")
                    
                    // Check if it's a directory
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: extractedURL.path, isDirectory: &isDirectory) {
                        print("📦 DEBUG: Is directory: \(isDirectory.boolValue)")
                        
                        if isDirectory.boolValue {
                            // Find vault files recursively in the extracted directory
                            let vaultFiles = self.findVaultFilesRecursively(in: extractedURL)
                            print("📁 DEBUG: Found \(vaultFiles.count) vault files in coordinator result")
                            for (index, file) in vaultFiles.enumerated() {
                                print("  File \(index + 1): \(file.lastPathComponent)")
                            }
                            
                            // Process vault files
                            importedVaults = self.processVaultFiles(vaultFiles)
                            print("✅ DEBUG: Processed \(importedVaults.count) vaults successfully")
                        } else {
                            print("❌ DEBUG: Coordinator didn't extract the ZIP")
                        }
                    }
                }
                
                if let error = coordinatorError {
                    print("❌ DEBUG: Coordinator error: \(error)")
                    throw ZipFileError.failedToExtractZIP(error.localizedDescription)
                }
            }
            
        } catch {
            print("❌ DEBUG: Error during extraction: \(error)")
            cleanupExtractedFiles()
            throw error
        }
        
        guard !importedVaults.isEmpty else {
            print("⚠️ DEBUG: No vaults imported from ZIP")
            cleanupExtractedFiles()
            showError("noVaultsFoundInZip")
            return
        }
        
        print("🎉 DEBUG: Setting up \(importedVaults.count) vaults for import")
        multipleVaultsToImport = importedVaults
        isMultipleVaultImport = true
        isFileUploaded = true
    }
    
    /// Recursively find vault files in a directory
    private func findVaultFilesRecursively(in directory: URL) -> [URL] {
        print("🔎 DEBUG: Searching recursively in: \(directory.path)")
        var vaultFiles: [URL] = []
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("❌ DEBUG: Failed to create enumerator for: \(directory.path)")
            return []
        }
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
                
                if resourceValues.isRegularFile == true {
                    let fileName = fileURL.lastPathComponent
                    
                    // Check if it's a vault file
                    let isVaultFile = fileName.hasSuffix(".bak") || 
                                     fileName.hasSuffix(".vult") || 
                                     fileName.hasSuffix(".dat")
                    
                    // Skip hidden files and macOS metadata
                    let isNotMetadata = !fileName.hasPrefix(".") && 
                                       !fileURL.path.contains("__MACOSX") &&
                                       !fileName.hasPrefix("._")
                    
                    if isVaultFile && isNotMetadata {
                        print("  ✅ Found vault file: \(fileName)")
                        vaultFiles.append(fileURL)
                    }
                }
            } catch {
                print("  ⚠️ Error checking file: \(fileURL.lastPathComponent) - \(error)")
            }
        }
        
        print("📊 DEBUG: Total vault files found: \(vaultFiles.count)")
        return vaultFiles
    }
    
    private func findVaultFiles(in extractedURL: URL) -> [URL] {
        print("🔎 DEBUG: findVaultFiles called with: \(extractedURL.path)")
        print("🔎 DEBUG: Is directory check: \(extractedURL.isDirectory)")
        
        guard extractedURL.isDirectory else { 
            print("🔎 DEBUG: Not a directory, returning single file")
            return [extractedURL] 
        }
        
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: extractedURL, includingPropertiesForKeys: [.isDirectoryKey]) else {
            print("❌ DEBUG: Failed to create enumerator")
            return []
        }
        
        var allFiles: [URL] = []
        var vaultFiles: [URL] = []
        
        for item in enumerator {
            guard let fileURL = item as? URL else { continue }
            allFiles.append(fileURL)
            
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                  !resourceValues.isDirectory! else { 
                print("  📂 Skipping directory: \(fileURL.lastPathComponent)")
                continue 
            }
            
            let fileName = fileURL.lastPathComponent
            print("  📄 Checking file: \(fileName)")
            
            let hasBak = fileName.hasSuffix(".bak")
            let hasVult = fileName.hasSuffix(".vult")
            let hasDat = fileName.hasSuffix(".dat")
            let isVaultFile = hasBak || hasVult || hasDat
            
            let startsWithDot = fileName.hasPrefix(".")
            let hasMacOSX = fileName.contains("__MACOSX")
            let isNotMetadata = !startsWithDot && !hasMacOSX
            
            print("    - .bak: \(hasBak), .vult: \(hasVult), .dat: \(hasDat)")
            print("    - Is vault file: \(isVaultFile)")
            print("    - Is not metadata: \(isNotMetadata)")
            
            if isVaultFile && isNotMetadata {
                print("    ✅ Added as vault file")
                vaultFiles.append(fileURL)
            } else {
                print("    ❌ Skipped")
            }
        }
        
        print("📊 DEBUG: Total files enumerated: \(allFiles.count)")
        print("📊 DEBUG: Vault files found: \(vaultFiles.count)")
        return vaultFiles
    }
    
    private func processVaultFiles(_ fileURLs: [URL]) -> [Vault] {
        print("🔄 DEBUG: Processing \(fileURLs.count) vault files")
        var processedVaults: [Vault] = []
        var encryptedVaultData: [(fileName: String, data: Data)] = []
        
        // First pass: collect all vaults, identify encrypted ones
        for fileURL in fileURLs {
            print("  📝 Processing: \(fileURL.lastPathComponent)")
            do {
                let fileData = try Data(contentsOf: fileURL)
                print("    📊 File size: \(fileData.count) bytes")
                
                // Check if it's an encrypted protobuf vault
                if let decodedContainer = Data(base64Encoded: fileData),
                   let vaultContainer = try? VSVaultContainer(serializedBytes: decodedContainer),
                   vaultContainer.isEncrypted {
                    print("    🔐 Found encrypted vault, will prompt for password")
                    if let vaultData = Data(base64Encoded: vaultContainer.vault) {
                        encryptedVaultData.append((fileName: fileURL.lastPathComponent, data: vaultData))
                    }
                } else if let vault = try decodeVaultFromData(fileData) {
                    print("    ✅ Successfully decoded unencrypted vault")
                    processedVaults.append(vault)
                } else {
                    print("    ⚠️ Vault decoded but returned nil")
                }
            } catch {
                print("    ❌ Failed: \(error.localizedDescription)")
                logger.warning("Failed to import vault from \(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        // Handle encrypted vaults separately
        if !encryptedVaultData.isEmpty {
            print("📱 Found \(encryptedVaultData.count) encrypted vault(s)")
            promptForPasswordAndImportMultiple(encryptedVaultData: encryptedVaultData, processedVaults: processedVaults)
            // Return empty for now, the password prompt will handle the import
            return []
        }
        
        return processedVaults
    }
    
    /// Decode a vault from file data
    private func decodeVaultFromData(_ data: Data) throws -> Vault? {
        print("    🔐 Attempting to decode vault data...")
        
        // Try protobuf format first
        if let vault = tryDecodeProtobuf(data) { 
            print("    ✅ Successfully decoded as protobuf")
            return vault 
        }
        print("    ❌ Not a protobuf format")
        
        // Try JSON formats
        let decoder = JSONDecoder()
        if let backupVault = try? decoder.decode(BackupVault.self, from: data) {
            print("    ✅ Successfully decoded as BackupVault JSON")
            return backupVault.vault
        }
        print("    ❌ Not a BackupVault JSON format")
        
        if let vault = try? decoder.decode(Vault.self, from: data) {
            print("    ✅ Successfully decoded as Vault JSON")
            return vault
        }
        print("    ❌ Not a Vault JSON format")
        
        print("    ❌ Failed to decode in any known format")
        return nil
    }
    
    private func tryDecodeProtobuf(_ data: Data) -> Vault? {
        guard let decodedContainer = Data(base64Encoded: data),
              let vaultContainer = try? VSVaultContainer(serializedBytes: decodedContainer),
              let vaultData = Data(base64Encoded: vaultContainer.vault) else {
            return nil
        }
        
        if vaultContainer.isEncrypted {
            // For single file imports, prompt for password
            if !isMultipleVaultImport {
                promptForPasswordAndImport(from: vaultData)
            }
            return nil
        }
        
        guard let vsVault = try? VSVault(serializedBytes: vaultData) else { return nil }
        return try? Vault(proto: vsVault)
    }
    
    
    func processEncryptedVaults(encryptedVaultData: [(fileName: String, data: Data)], processedVaults: [Vault], password: String) {
        var allVaults = processedVaults
        var failedVaults: [String] = []
        
        for (fileName, vaultData) in encryptedVaultData {
            print("🔓 Attempting to decrypt: \(fileName)")
            
            // Try to decrypt the vault data
            if let decryptedString = decryptOrReadData(data: vaultData, password: password) {
                // Parse the decrypted vault
                do {
                    let hexData = Data(hexString: decryptedString) ?? Data()
                    if let vsVault = try? VSVault(serializedBytes: hexData),
                       let vault = try? Vault(proto: vsVault) {
                        print("  ✅ Successfully decrypted and parsed: \(fileName)")
                        allVaults.append(vault)
                    } else {
                        print("  ❌ Failed to parse decrypted data: \(fileName)")
                        failedVaults.append(fileName)
                    }
                } catch {
                    print("  ❌ Error parsing vault: \(error)")
                    failedVaults.append(fileName)
                }
            } else {
                print("  ❌ Failed to decrypt: \(fileName)")
                failedVaults.append(fileName)
            }
        }
        
        // Update the vaults to import
        self.multipleVaultsToImport = allVaults
        self.isMultipleVaultImport = true
        self.isFileUploaded = true
        
        // Show warning if some vaults failed
        if !failedVaults.isEmpty {
            let failedList = failedVaults.joined(separator: ", ")
            self.showAlert = true
            self.alertTitle = "Failed to decrypt: \(failedList). Successfully imported \(allVaults.count) vault(s)."
        }
    }
    
    /// Restore multiple vaults to the database
    func restoreMultipleVaults(modelContext: ModelContext, vaults: [Vault]) {
        let results = importVaults(multipleVaultsToImport, to: modelContext, existing: vaults)
        
        selectedVault = results.imported.first
        showImportResults(results)
        cleanup()
    }
    
    private func importVaults(_ vaultsToImport: [Vault], to modelContext: ModelContext, existing: [Vault]) -> (imported: [Vault], duplicates: Int) {
        var imported: [Vault] = []
        var duplicates = 0
        
        for vault in vaultsToImport {
            if isVaultUnique(backupVault: vault, vaults: existing + imported) {
                VaultDefaultCoinService(context: modelContext).setDefaultCoinsOnce(vault: vault)
                modelContext.insert(vault)
                imported.append(vault)
            } else {
                duplicates += 1
            }
        }
        
        return (imported, duplicates)
    }
    
    private func showImportResults(_ results: (imported: [Vault], duplicates: Int)) {
        let successCount = results.imported.count
        
        if successCount > 0 {
            alertTitle = successCount == 1 ? "vaultImportedSuccessfully" : "vaultsImportedSuccessfully"
            showAlert = false
            isLinkActive = true
        } else if results.duplicates > 0 {
            showError("vaultAlreadyExists")
        } else {
            showError("vaultRestoreFailed")
        }
    }
    
    private func cleanup() {
        cleanupExtractedFiles()
        multipleVaultsToImport = []
        isMultipleVaultImport = false
    }
    
    func showError(_ message: String) {
        alertTitle = message
        showAlert = true
        isLinkActive = false
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
    
    func restoreVaultBack(modelContext: ModelContext,vaults: [Vault], vaultData: Data) {
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
                .setDefaultCoinsOnce(vault: vault)
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
    
    func restoreVault(modelContext: ModelContext, vaults: [Vault]) {
        guard let vaultText = decryptedContent, let vaultData = Data(hexString: vaultText) else {
            alertTitle = "invalidVaultData"
            showAlert = true
            isLinkActive = false
            return
        }
        
        if isBakFile() {
            restoreVaultBack(modelContext: modelContext, vaults: vaults, vaultData: vaultData)
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
                .setDefaultCoinsOnce(vault: backupVault.vault)
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
                    .setDefaultCoinsOnce(vault: vault)
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
        
        if fileExtension == "dat" || fileExtension == "bak" || fileExtension == "vult" || fileExtension == "txt" || fileExtension == "zip" {
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
                importedFileName = url.lastPathComponent.replacingOccurrences(of: ".txt", with: ".vult")
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
        importedFileName = url.lastPathComponent.replacingOccurrences(of: ".txt", with: ".vult")
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
                            self.importedFileName = url.lastPathComponent.replacingOccurrences(of: ".txt", with: ".vult")
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

