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

/// What to do with an incoming backup vault, decided before it ever reaches
/// `modelContext.insert`.
///
/// `Vault` marks `name`, `pubKeyECDSA`, `pubKeyEdDSA` and `publicKeyMLDSA44` as
/// `@Attribute(.unique)`. SwiftData turns an insert that collides on any one of
/// them into an *upsert*: the incoming row replaces the stored one and the
/// stored vault's key shares go with it, with nothing thrown and nothing logged.
/// So "is this a duplicate?" and "can this be stored without clobbering
/// something?" are two separate questions, and both have to be answered.
enum VaultImportDecision: Equatable {
    /// Safe to store. `name` is the backup's own name, disambiguated when a
    /// vault already on the device holds it.
    case insert(name: String)
    /// The same vault is already on the device — it shares key material.
    case duplicate
    /// The backup would still collide on a unique attribute after its name was
    /// resolved, and the colliding value carries no identity (an empty public
    /// key), so it cannot be called a duplicate either. Storing it would
    /// overwrite a stored vault, so it is refused.
    case unsafeCollision
}

@MainActor
class EncryptedBackupViewModel: ObservableObject {
    /// Outcome of a multi-vault (zip) import. `unsafeNames` is kept apart from
    /// `skippedNames` because "already on this device" and "refusing to
    /// overwrite what is on this device" are different things to tell the user.
    typealias ImportResults = (imported: [Vault], duplicates: Int, skippedNames: [String], unsafeNames: [String])

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

    private let logger = Log.wallet.other
    private let keychain = DefaultKeychainService.shared
    private let backupEncryption: VaultBackupEncryption = Pbkdf2VaultBackupEncryption()

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

    func exportFileWithoutPassword(_ backupType: VaultBackupType) async -> FileExporterModel<EncryptedDataFile>? {
        return try? await createBackupFile(backupType, encryptionPassword: nil)
    }

    func exportFileWithVaultPassword(_ backupType: VaultBackupType) async -> FileExporterModel<EncryptedDataFile>? {
        // Either way there is no password to encrypt with, and the export is
        // abandoned rather than written unprotected — so an unreadable Keychain
        // takes the same branch as an absent password.
        let saved = keychain.getFastPassword(pubKeyECDSA: backupType.vault.pubKeyECDSA)
        guard let vaultPassword = saved.valueTreatingUnavailableAsAbsent else {
            logger.warning("Couldn't fetch password for vault")
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
        case .multiple(let vaults, _):
            return try await createMultipleBackupFile(vaults: vaults, encryptionPassword: encryptionPassword)
        }
    }

    func createMultipleBackupFile(vaults: [Vault], encryptionPassword: String?) async throws -> FileExporterModel<EncryptedDataFile>? {
        let timestamp = Int(Date().timeIntervalSince1970)
        let backupFolderName = "vultisig_backups_\(timestamp)"
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(backupFolderName)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        for vault in vaults {
            _ = try await generateBackupFile(vault: vault, encryptionPassword: encryptionPassword, targetDirectory: tempDir)
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

    func generateBackupFile(vault: Vault, encryptionPassword: String?, targetDirectory: URL? = nil) async throws -> URL? {
        var vaultContainer = VSVaultContainer()
        vaultContainer.version = 1 // current version 1
        let vsVault = vault.mapToProtobuff()
        let data = try vsVault.serializedData()

        if let encryptionPassword {
            guard let encryptedData = await encrypt(data: data, password: encryptionPassword) else {
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
        let tempURL = try await generateBackupFile(vault: vault, encryptionPassword: encryptionPassword)
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

    private func encrypt(data: Data, password: String) async -> Data? {
        do {
            return try await backupEncryption.encrypt(data: data, password: password)
        } catch {
            logger.error("Error encrypting backup data: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func importDragDropFile(content: Data) async {
        do {
            if isBakFile() {
                try importBakFile(data: content)
                return
            }

            if let decryptedString = await decryptOrReadData(data: content, password: "") {
                decryptedContent = decryptedString
                isFileUploaded = true
            } else {
                promptForPasswordAndImport(from: content)
            }
        } catch {
            logger.error("Error reading file: \(error.localizedDescription, privacy: .public)")
        }
    }

    // Import
    func importFile(from url: URL) async {
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

            if let decryptedString = await decryptOrReadData(data: data, password: "") {
                decryptedContent = decryptedString
                isFileUploaded = true
            } else {
                promptForPasswordAndImport(from: data)
            }
        } catch {
            logger.error("Error reading file: \(error.localizedDescription, privacy: .public)")
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
                logger.error("⚠️ unzipItem failed: \(error.localizedDescription, privacy: .public)")
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
                            self.logger.error("❌ Coordinator didn't extract the ZIP")
                        }
                    }
                }

                if let error = coordinatorError {
                    self.logger.error("❌ Coordinator error: \(error.localizedDescription, privacy: .public)")
                    throw ZipFileError.failedToExtractZIP(error.localizedDescription)
                }
            }

        } catch {
            logger.error("❌ Error during extraction: \(error.localizedDescription, privacy: .public)")
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
            logger.error("❌ Failed to create enumerator for: \(directory.path, privacy: .public)")
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
                logger.warning("⚠️ Error checking file: \(fileURL.lastPathComponent, privacy: .public) - \(error.localizedDescription, privacy: .public)")
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
                logger.error("❌ Failed: \(error.localizedDescription, privacy: .public)")
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

    func processEncryptedVaults(encryptedVaultData: [(fileName: String, data: Data)], processedVaults: [Vault], password: String) async {
        var allVaults = processedVaults
        var failedVaults: [String] = []

        for (fileName, vaultData) in encryptedVaultData {
            // Decrypt the vault data (returns raw protobuf bytes, not text)
            if let decryptedData = await decrypt(data: vaultData, password: password) {
                // Parse the decrypted protobuf bytes directly
                do {
                    let vsVault = try VSVault(serializedBytes: decryptedData)
                    let vault = try Vault(proto: vsVault)
                    allVaults.append(vault)
                } catch {
                    logger.error("❌ Failed to parse decrypted data (\(fileName, privacy: .public)): \(error.localizedDescription, privacy: .public)")
                    failedVaults.append(fileName)
                }
            } else {
                logger.error("❌ Failed to decrypt: \(fileName, privacy: .public)")
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

    private func importVaults(_ vaultsToImport: [Vault], to modelContext: ModelContext, existing: [Vault]) -> ImportResults {
        var imported: [Vault] = []
        var duplicates = 0
        var skippedNames: [String] = []
        var unsafeNames: [String] = []

        for vault in vaultsToImport {
            // `imported` carries the already-resolved names, so a batch that
            // contains two vaults called "Savings" disambiguates the second
            // against the first rather than upserting it.
            switch insertIfSafe(vault, existing: existing + imported, modelContext: modelContext) {
            case .insert:
                imported.append(vault)
            case .duplicate:
                duplicates += 1
                skippedNames.append(vault.name)
                logger.info("Skipped duplicate vault during zip import: \(vault.name)")
            case .unsafeCollision:
                unsafeNames.append(vault.name)
                logger.error("Refused a vault during zip import: storing it would have overwritten a vault already on this device")
            }
        }

        return (imported, duplicates, skippedNames, unsafeNames)
    }

    func showImportResults(_ results: ImportResults) {
        let successCount = results.imported.count
        let duplicateCount = results.duplicates

        // A backup refused because storing it would have overwritten a vault on
        // the device is not "already imported" — it gets its own message rather
        // than being folded into the duplicate count.
        if !results.unsafeNames.isEmpty {
            alertTitle = String(
                format: NSLocalizedString("zipImportUnsafeVaults", comment: ""),
                successCount,
                duplicateCount + results.unsafeNames.count,
                results.unsafeNames.joined(separator: ", ")
            )
            showAlert = true
            isVaultImported = successCount > 0
            return
        }

        if successCount > 0 && duplicateCount > 0 {
            // Mixed: some imported, some skipped
            let skipped = results.skippedNames.joined(separator: ", ")
            alertTitle = String(
                format: NSLocalizedString("zipImportPartialSuccess", comment: ""),
                successCount, duplicateCount, skipped
            )
            showAlert = true
            isVaultImported = true
        } else if successCount > 0 {
            alertTitle = successCount == 1 ? "vaultImportedSuccessfully" : "vaultsImportedSuccessfully"
            showAlert = false
            isVaultImported = true
        } else if duplicateCount > 0 {
            let skipped = results.skippedNames.joined(separator: ", ")
            alertTitle = String(
                format: NSLocalizedString("zipImportAllDuplicates", comment: ""),
                duplicateCount, skipped
            )
            showAlert = true
            isVaultImported = false
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

    func importFileWithPassword(from data: Data, password: String) async {
        if let decryptedData = await decrypt(data: data, password: password) {
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

    func decryptOrReadData(data: Data, password: String) async -> String? {
        if password.isEmpty {
            return String(data: data, encoding: .utf8)
        } else {
            return await decrypt(data: data, password: password).flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    func decrypt(data: Data, password: String) async -> Data? {
        return await backupEncryption.decrypt(data: data, password: password)
    }

    func isDKLS(filename: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: "share\\d+of\\d+") // share2of3, share3of5
            let matches = regex.matches(in: filename, range: NSRange(filename.startIndex..., in: filename))
            return !matches.isEmpty
        } catch {
            logger.error("Error checking if filename is a DKLS backup: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func restoreVaultBack(modelContext: ModelContext, vaults: [Vault], vaultData: Data) {
        do {
            let vsVault = try VSVault(serializedBytes: vaultData)
            let vault = try Vault(proto: vsVault)
            if isDKLS(filename: self.importedFileName ?? ""), vault.libType != LibType.GG20, vault.libType != LibType.KeyImport {
                vault.libType = LibType.DKLS
            }

            switch insertIfSafe(vault, existing: vaults, modelContext: modelContext) {
            case .insert:
                selectedVault = vault
                isVaultImported = true
            case .duplicate:
                showError("vaultAlreadyExists")
            case .unsafeCollision:
                showError("vaultImportWouldOverwriteExisting")
            }
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
            switch insertIfSafe(backupVault.vault, existing: vaults, modelContext: modelContext) {
            case .insert:
                selectedVault = backupVault.vault
                showAlert = false
                isVaultImported = true
            case .duplicate:
                showError("vaultAlreadyExists")
            case .unsafeCollision:
                showError("vaultImportWouldOverwriteExisting")
            }
        } catch {
            logger.warning("failed to import with new format , fallback to the old format instead. \(error.localizedDescription, privacy: .public)")

            // fallback
            do {
                let vault = try decoder.decode(Vault.self, from: vaultData)

                switch insertIfSafe(vault, existing: vaults, modelContext: modelContext) {
                case .insert:
                    selectedVault = vault
                    showAlert = false
                    isVaultImported = true
                case .duplicate:
                    showError("vaultAlreadyExists")
                case .unsafeCollision:
                    showError("vaultImportWouldOverwriteExisting")
                }
            } catch {
                logger.error("fail to restore vault: \(error.localizedDescription)")
                alertTitle = "vaultRestoreFailed"
                showAlert = true
                isVaultImported = false
            }
        }
    }

    // MARK: - Import safety

    /// "Is this the same vault we already have?"
    ///
    /// A vault cannot legitimately share a public key with a *different* vault,
    /// so a match on any single key means the same key material — one shared key
    /// and one differing key is not a distinct vault, it is a sign something is
    /// wrong. Empty/absent keys carry no identity and never count as a match;
    /// whether they are safe to store is the separate question that
    /// ``importDecision(for:existing:)`` answers.
    func isVaultUnique(backupVault: Vault, vaults: [Vault]) -> Bool {
        let ecdsa = backupVault.pubKeyECDSA.nilIfEmpty
        let eddsa = backupVault.pubKeyEdDSA.nilIfEmpty
        let mldsa = backupVault.publicKeyMLDSA44?.nilIfEmpty

        for vault in vaults {
            if let ecdsa, vault.pubKeyECDSA == ecdsa { return false }
            if let eddsa, vault.pubKeyEdDSA == eddsa { return false }
            if let mldsa, vault.publicKeyMLDSA44?.nilIfEmpty == mldsa { return false }
        }
        return true
    }

    /// "Can this vault be stored without overwriting one already on the device?"
    ///
    /// A name collision between two genuinely different vaults is resolved, not
    /// rejected — the name is user-chosen and `Main`/`Savings`/`Test` are exactly
    /// the names people reuse across devices. Anything still colliding after that
    /// is refused: `pubKeyECDSA`/`pubKeyEdDSA` default to `""`, and `""` is a
    /// real value in the unique index, so two key-less backups would upsert each
    /// other. The final check restates the raw index semantics — one clause per
    /// `@Attribute(.unique)` field on `Vault` — rather than reusing the duplicate
    /// rule, whose empty/`nil` tolerance is exactly what would let those through.
    /// It is the single place to extend when a unique attribute is added.
    func importDecision(for backupVault: Vault, existing: [Vault]) -> VaultImportDecision {
        guard isVaultUnique(backupVault: backupVault, vaults: existing) else {
            return .duplicate
        }

        let name = availableVaultName(basedOn: backupVault.name, taken: Set(existing.map(\.name)))

        let collides = existing.contains { vault in
            vault.name == name
                || vault.pubKeyECDSA == backupVault.pubKeyECDSA
                || vault.pubKeyEdDSA == backupVault.pubKeyEdDSA
                || (vault.publicKeyMLDSA44 != nil && vault.publicKeyMLDSA44 == backupVault.publicKeyMLDSA44)
        }
        guard !collides else { return .unsafeCollision }

        return .insert(name: name)
    }

    /// A vault name no stored vault holds, derived from the backup's own name
    /// (`Savings` → `Savings (2)`) so the user keeps the name they chose rather
    /// than a generated one. Terminates by pigeonhole: at most `taken.count`
    /// names are unavailable, and the scan covers `taken.count + 1` candidates.
    func availableVaultName(basedOn name: String, taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }

        var suffix = 2
        var candidate = "\(name) (\(suffix))"
        while taken.contains(candidate), suffix <= taken.count + 1 {
            suffix += 1
            candidate = "\(name) (\(suffix))"
        }
        return candidate
    }

    /// Runs the import gate and stores `vault` when it is safe to store,
    /// renaming it first if the backup's own name is already taken. Returns the
    /// decision so the caller can surface the outcome.
    private func insertIfSafe(_ vault: Vault, existing: [Vault], modelContext: ModelContext) -> VaultImportDecision {
        let decision = importDecision(for: vault, existing: existing)
        guard case .insert(let name) = decision else { return decision }

        if vault.name != name {
            logger.info("Renamed an imported vault to avoid colliding with a stored vault's name")
            vault.name = name
        }
        VaultDefaultCoinService(context: modelContext).setDefaultCoinsOnce(vault: vault)
        modelContext.insert(vault)
        return decision
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
                Task { @MainActor in
                    await importFile(from: url)
                }
            }
        case .failure(let error):
            logger.error("Error importing file: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleFileDocument(_ url: URL) {
        guard isValidFormat(url) else {
            showInvalidFormatAlert()
            return
        }
        importedFileName = url.lastPathComponent.replacingOccurrences(of: ".txt", with: ".vult")
        Task { @MainActor in
            await importFile(from: url)
        }
    }

    func handleOnDrop(providers: [NSItemProvider]) async {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.data.identifier) }) else {
            logger.error("Invalid file type.")
            return
        }
        do {
            let dragDropData = try await provider.loadItem(forTypeIdentifier: UTType.data.identifier)
            if let urlData = dragDropData as? NSURL {
                logger.debug("File Path as NSURL: \(String(describing: urlData), privacy: .public)")
                provider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data, _ in
                    if let data {
                        let url = urlData as URL
                        Task { @MainActor in
                            guard self.isValidFormat(url) else {
                                self.showInvalidFormatAlert()
                                return
                            }
                            self.importedFileName = url.lastPathComponent.replacingOccurrences(of: ".txt", with: ".vult")
                            await self.importDragDropFile(content: data)
                        }
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.alertTitle = "failedToLoadFileData"
                self.showAlert = true
            }
            logger.error("fail to process drag and drop file: \(error.localizedDescription, privacy: .public)")
        }
    }
}

#if os(iOS)
import SwiftUI
import UIKit

extension EncryptedBackupViewModel {
    func promptForPasswordAndImport(from data: Data) {
        let alert = UIAlertController(title: NSLocalizedString("enterPassword", comment: ""), message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.isSecureTextEntry = true
            textField.placeholder = NSLocalizedString("password", comment: "").capitalized
        }
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            if let password = alert.textFields?.first?.text {
                Task { @MainActor in
                    self.decryptionPassword = password
                    await self.importFileWithPassword(from: data, password: password)
                }
            }
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        if let rootViewController = UIApplication.shared.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true, completion: nil)
        }
    }

    func promptForPasswordAndImportMultiple(encryptedVaultData: [(fileName: String, data: Data)], processedVaults: [Vault]) {
        let message = String(format: NSLocalizedString("Found %d encrypted vault(s). Enter password to decrypt:", comment: ""), encryptedVaultData.count)
        let alert = UIAlertController(title: NSLocalizedString("enterPassword", comment: ""), message: message, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.isSecureTextEntry = true
            textField.placeholder = NSLocalizedString("password", comment: "").capitalized
        }
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            if let password = alert.textFields?.first?.text {
                Task { @MainActor in
                    self.decryptionPassword = password
                    await self.processEncryptedVaults(encryptedVaultData: encryptedVaultData, processedVaults: processedVaults, password: password)
                }
            }
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
            // Clear pending encrypted vaults on cancel
            self.pendingEncryptedVaults = []

            // If user cancels, still import the non-encrypted vaults
            if !processedVaults.isEmpty {
                self.multipleVaultsToImport = processedVaults
                self.isMultipleVaultImport = true
                self.isFileUploaded = true
            } else {
                self.showError(NSLocalizedString("noUnencryptedVaultsToImport", comment: "Shown when there are no unencrypted vaults available to import"))
            }
        }))

        if let rootViewController = UIApplication.shared.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true, completion: nil)
        }
    }
}
#endif

#if os(macOS)
import SwiftUI
import AppKit

extension EncryptedBackupViewModel {
    func promptForPasswordAndImport(from data: Data) {
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
            let alertWindow = alert.window
            let screenFrame = NSScreen.main?.frame ?? NSRect.zero
            let alertFrame = alertWindow.frame
            let centerX = screenFrame.midX - alertFrame.width / 2
            let centerY = screenFrame.midY - alertFrame.height / 2
            alertWindow.setFrameOrigin(NSPoint(x: centerX, y: centerY))

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let password = textField.stringValue
                Task { @MainActor in
                    self.decryptionPassword = password
                    await self.importFileWithPassword(from: data, password: password)
                }
            }
            return
        }

        // Show the alert as a sheet attached to the main window
        alert.beginSheetModal(for: mainWindow) { response in
            if response == .alertFirstButtonReturn {
                let password = textField.stringValue
                Task { @MainActor in
                    self.decryptionPassword = password
                    await self.importFileWithPassword(from: data, password: password)
                }
            }
        }
    }

    func promptForPasswordAndImportMultiple(encryptedVaultData: [(fileName: String, data: Data)], processedVaults: [Vault]) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("enterPassword", comment: "")
        alert.informativeText = String(format: NSLocalizedString("Found %d encrypted vault(s). Enter password to decrypt:", comment: ""), encryptedVaultData.count)
        alert.alertStyle = .informational

        let textField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.placeholderString = NSLocalizedString("password", comment: "").capitalized
        alert.accessoryView = textField

        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                let password = textField.stringValue
                Task { @MainActor in
                    self.decryptionPassword = password
                    await self.processEncryptedVaults(encryptedVaultData: encryptedVaultData, processedVaults: processedVaults, password: password)
                }
            } else if response == .alertSecondButtonReturn {
                // Clear pending encrypted vaults on cancel
                self.pendingEncryptedVaults = []

                // If user cancels, still import the non-encrypted vaults
                if !processedVaults.isEmpty {
                    self.multipleVaultsToImport = processedVaults
                    self.isMultipleVaultImport = true
                    self.isFileUploaded = true
                } else {
                    self.showError(NSLocalizedString("noUnencryptedVaultsToImport", comment: "Shown when there are no unencrypted vaults available to import"))
                }
            }
        }

        guard let mainWindow = NSApplication.shared.mainWindow else {
            let alertWindow = alert.window
            let screenFrame = NSScreen.main?.frame ?? NSRect.zero
            let alertFrame = alertWindow.frame
            let centerX = screenFrame.midX - alertFrame.width / 2
            let centerY = screenFrame.midY - alertFrame.height / 2
            alertWindow.setFrameOrigin(NSPoint(x: centerX, y: centerY))

            let response = alert.runModal()
            handleResponse(response)
            return
        }

        // Show the alert as a sheet attached to the main window
        alert.beginSheetModal(for: mainWindow) { response in
            handleResponse(response)
        }
    }
}
#endif
