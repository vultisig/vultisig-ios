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
    @Published var isVaultImported: Bool = false
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
        pendingEncryptedVaults = []
    }

    /// Cleanup extracted files from zip import
    private func cleanupExtractedFiles() {
        guard let extractionDir = extractedFilesDirectory else { return }
        try? FileManager.default.removeItem(at: extractionDir)
        extractedFilesDirectory = nil
    }

    func exportFileWithoutPassword(_ backupType: VaultBackupType) -> FileExporterModel<EncryptedDataFile>? {
        return try? createBackupFile(backupType, encryptionPassword: nil)
    }

    func exportFileWithVaultPassword(_ backupType: VaultBackupType) -> FileExporterModel<EncryptedDataFile>? {
        guard let vaultPassword = keychain.getFastPassword(pubKeyECDSA: backupType.vault.pubKeyECDSA) else {
            debugPrint("Couldn't fetch password for vault")
            return nil
        }

        return try? createBackupFile(backupType, encryptionPassword: vaultPassword)
    }

    func exportFileWithCustomPassword(_ backupType: VaultBackupType) -> FileExporterModel<EncryptedDataFile>? {
        return try? createBackupFile(backupType, encryptionPassword: encryptionPassword)
    }

    func createBackupFile(_ backupType: VaultBackupType, encryptionPassword: String?) throws -> FileExporterModel<EncryptedDataFile>? {
        switch backupType {
        case .single(let vault):
            return try createSingleBackupFile(vault: vault, encryptionPassword: encryptionPassword)
        case .multiple(let vaults, _):
            return try createMultipleBackupFile(vaults: vaults, encryptionPassword: encryptionPassword)
        }
    }

    func createMultipleBackupFile(vaults: [Vault], encryptionPassword: String?) throws -> FileExporterModel<EncryptedDataFile>? {
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

    func createSingleBackupFile(vault: Vault, encryptionPassword: String?) throws -> FileExporterModel<EncryptedDataFile>? {
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

    func importDragDropFile(content: Data) {
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
        _ = url.startAccessingSecurityScopedResource()
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
        var importedVaults: [Vault] = []

        // Create a temporary directory for extraction
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("VultisigZipExtract_\(UUID().uuidString)")

        do {
            // Create temp directory
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            self.extractedFilesDirectory = tempDir

            // Try to extract using FileManager's built-in unzip (iOS 15+)
            var extractedSuccessfully = false

            // Try to extract on all platforms using ZIPFoundation via FileManagerExtension
            do {
                // Create a subdirectory for extraction
                let extractDir = tempDir.appendingPathComponent("extracted")
                try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true, attributes: nil)

                try fileManager.unzipItem(at: zipURL, to: extractDir)

                self.extractedFilesDirectory = extractDir
                extractedSuccessfully = true

                let vaultFiles = findVaultFilesRecursively(in: extractDir)

                importedVaults = processVaultFiles(vaultFiles)
            } catch {
                print("⚠️ DEBUG: unzipItem failed: \(error)")
                extractedSuccessfully = false
            }

            // Fallback: Use NSFileCoordinator
            if !extractedSuccessfully {
                var coordinatorError: NSError?
                let coordinator = NSFileCoordinator(filePresenter: nil)

                coordinator.coordinate(readingItemAt: zipURL, options: [.forUploading], error: &coordinatorError) { (extractedURL) in

                    // Check if it's a directory
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: extractedURL.path, isDirectory: &isDirectory) {

                        if isDirectory.boolValue {
                            // Find vault files recursively in the extracted directory
                            let vaultFiles = self.findVaultFilesRecursively(in: extractedURL)

                            // Process vault files
                            importedVaults = self.processVaultFiles(vaultFiles)
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

        // Only show error if no vaults found AND no encrypted vaults pending password
        if importedVaults.isEmpty && pendingEncryptedVaults.isEmpty {
            cleanupExtractedFiles()
            showError("noVaultsFoundInZip")
            return
        }

        // If we have unencrypted vaults, set them up for import
        if !importedVaults.isEmpty {
            multipleVaultsToImport = importedVaults
            isMultipleVaultImport = true
            isFileUploaded = true
        }
        // If only encrypted vaults, the password prompt will handle the rest
    }

    /// Recursively find vault files in a directory
    private func findVaultFilesRecursively(in directory: URL) -> [URL] {
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
                        vaultFiles.append(fileURL)
                    }
                }
            } catch {
                print("  ⚠️ Error checking file: \(fileURL.lastPathComponent) - \(error)")
            }
        }

        return vaultFiles
    }

    private func processVaultFiles(_ fileURLs: [URL]) -> [Vault] {
        var processedVaults: [Vault] = []
        var encryptedVaultData: [(fileName: String, data: Data)] = []

        // First pass: collect all vaults, identify encrypted ones
        for fileURL in fileURLs {
            do {
                let fileData = try Data(contentsOf: fileURL)

                // Check if it's an encrypted protobuf vault
                if let decodedContainer = Data(base64Encoded: fileData),
                   let vaultContainer = try? VSVaultContainer(serializedBytes: decodedContainer),
                   vaultContainer.isEncrypted {
                    if let vaultData = Data(base64Encoded: vaultContainer.vault) {
                        encryptedVaultData.append((fileName: fileURL.lastPathComponent, data: vaultData))
                    }
                } else if let vault = try decodeVaultFromData(fileData) {
                    processedVaults.append(vault)
                }
            } catch {
                print("    ❌ Failed: \(error.localizedDescription)")
                logger.warning("Failed to import vault from \(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        // Handle encrypted vaults separately
        if !encryptedVaultData.isEmpty {
            self.pendingEncryptedVaults = encryptedVaultData
            promptForPasswordAndImportMultiple(encryptedVaultData: encryptedVaultData, processedVaults: processedVaults)
            // Return the unencrypted ones now; the password prompt will handle the encrypted ones
            return processedVaults
        }

        return processedVaults
    }

    /// Decode a vault from file data
    private func decodeVaultFromData(_ data: Data) throws -> Vault? {
        // Try protobuf format first
        if let vault = tryDecodeProtobuf(data) {
            return vault
        }

        // Try JSON formats
        let decoder = JSONDecoder()
        if let backupVault = try? decoder.decode(BackupVault.self, from: data) {
            return backupVault.vault
        }

        if let vault = try? decoder.decode(Vault.self, from: data) {
            return vault
        }
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
            // Decrypt the vault data (returns raw protobuf bytes, not text)
            if let decryptedData = decrypt(data: vaultData, password: password) {
                // Parse the decrypted protobuf bytes directly
                do {
                    let vsVault = try VSVault(serializedBytes: decryptedData)
                    let vault = try Vault(proto: vsVault)
                    allVaults.append(vault)
                } catch {
                    print("  ❌ Failed to parse decrypted data (\(fileName)): \(error.localizedDescription)")
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

        // Clear pending encrypted vaults after processing
        self.pendingEncryptedVaults = []

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
            isVaultImported = true
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
        pendingEncryptedVaults = []
    }

    func showError(_ message: String) {
        alertTitle = message
        showAlert = true
        isVaultImported = false
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
        do {
            let regex = try NSRegularExpression(pattern: "share\\d+of\\d+") // share2of3, share3of5
            let matches = regex.matches(in: filename, range: NSRange(filename.startIndex..., in: filename))
            return !matches.isEmpty
        } catch {
            print("Error checking if filename is a DKLS backup: \(error.localizedDescription)")
            return false
        }
    }

    func restoreVaultBack(modelContext: ModelContext, vaults: [Vault], vaultData: Data) {
        do {
            let vsVault = try VSVault(serializedBytes: vaultData)
            let vault = try Vault(proto: vsVault)
            if !isVaultUnique(backupVault: vault, vaults: vaults) {
                alertTitle = "vaultAlreadyExists"
                showAlert = true
                isVaultImported = false
                return
            }
            if isDKLS(filename: self.importedFileName ?? ""), vault.libType != LibType.GG20, vault.libType != LibType.KeyImport {
                vault.libType = LibType.DKLS
            }

            VaultDefaultCoinService(context: modelContext)
                .setDefaultCoinsOnce(vault: vault)
            modelContext.insert(vault)
            selectedVault = vault
            isVaultImported = true
        } catch {
            logger.error("fail to restore vault: \(error.localizedDescription)")
            alertTitle = "vaultRestoreFailed"
            showAlert = true
            isVaultImported = false
        }
    }

    func restoreVault(modelContext: ModelContext, vaults: [Vault]) {
        guard let vaultText = decryptedContent, let vaultData = Data(hexString: vaultText) else {
            alertTitle = "invalidVaultData"
            showAlert = true
            isVaultImported = false
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
            if !isVaultUnique(backupVault: backupVault.vault, vaults: vaults) {
                alertTitle = "vaultAlreadyExists"
                showAlert = true
                isVaultImported = false
                return
            }
            VaultDefaultCoinService(context: modelContext)
                .setDefaultCoinsOnce(vault: backupVault.vault)
            modelContext.insert(backupVault.vault)
            selectedVault = backupVault.vault
            showAlert = false
            isVaultImported = true
        } catch {
            print("failed to import with new format , fallback to the old format instead. \(error.localizedDescription)")

            // fallback
            do {
                let vault = try decoder.decode(Vault.self, from: vaultData)

                if !isVaultUnique(backupVault: vault, vaults: vaults) {
                    alertTitle = "vaultAlreadyExists"
                    showAlert = true
                    isVaultImported = false
                    return
                }
                VaultDefaultCoinService(context: modelContext)
                    .setDefaultCoinsOnce(vault: vault)
                modelContext.insert(vault)
                selectedVault = vault
                showAlert = false
                isVaultImported = true
            } catch {
                logger.error("fail to restore vault: \(error.localizedDescription)")
                alertTitle = "vaultRestoreFailed"
                showAlert = true
                isVaultImported = false
            }
        }
    }

    private func isVaultUnique(backupVault: Vault, vaults: [Vault]) -> Bool {
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
        do {
            let dragDropData = try await provider.loadItem(forTypeIdentifier: UTType.data.identifier)
            if let urlData = dragDropData as? NSURL {
                print("File Path as NSURL: \(urlData)")
                provider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data, _ in
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
            DispatchQueue.main.async {
                self.alertTitle = "failedToLoadFileData"
                self.showAlert = true
            }
            print("fail to process drag and drop file: \(error.localizedDescription)")
        }
    }
}
