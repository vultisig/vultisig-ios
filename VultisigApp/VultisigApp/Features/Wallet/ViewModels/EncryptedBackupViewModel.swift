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
    /// The device already holds this vault, and holds it in a form it can no
    /// longer open: every one of its key shares is sealed and the key that
    /// unseals them is confirmed gone. Skipping it as a duplicate is what makes
    /// the recovery advice — "restore from your `.vult`" — a dead end, so the
    /// stored row is replaced instead.
    ///
    /// `name` is the backup's own name, disambiguated against every stored
    /// vault **except** the one being replaced: that one is on its way out, so
    /// its name is not taken.
    case replaceOrphaned(name: String)
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
    /// Every format below reaches storage through this and only through this.
    /// `Vault.init(from: Decoder)` decodes `[KeyShare]` straight off the wire, so
    /// the JSON paths would otherwise write plaintext shares into a store that
    /// has a passcode set.
    private let importer: ProtectedVaultImporter
    /// Only ``KeyshareProtecting/isSealed(_:)`` is used, which reads the stored
    /// form and consults no state — so this cannot disagree with the importer's
    /// own protector about what a sealed value looks like.
    private let protector: KeyshareProtecting
    /// Read to tell "this device is locked" from "the key is gone", which is the
    /// difference between refusing an import and completing a recovery.
    private let keyStore: KeyshareKeyStoring

    init(
        importer: ProtectedVaultImporter = ProtectedVaultImporter(),
        protector: KeyshareProtecting = KeyshareProtector.shared,
        keyStore: KeyshareKeyStoring = DefaultKeyshareKeyStore.shared
    ) {
        self.importer = importer
        self.protector = protector
        self.keyStore = keyStore
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
        pendingEncryptedVaults = []
    }

    /// Cleanup extracted files from zip import
    private func cleanupExtractedFiles() {
        guard let extractionDir = extractedFilesDirectory else { return }
        try? FileManager.default.removeItem(at: extractionDir)
        extractedFilesDirectory = nil
    }

    func exportFileWithoutPassword(_ backupType: VaultBackupType) async -> FileExporterModel<EncryptedDataFile>? {
        return await backupFileReportingFailure(backupType, encryptionPassword: nil)
    }

    /// The two ways a backup can fail without throwing.
    ///
    /// Both were previously expressed as a `nil` return, which is how they got
    /// lost: a `nil` reads as "nothing to export" at every call site, and no
    /// call site could tell it apart from a refusal.
    enum BackupError: Error {
        /// A vault's file was not produced. Fatal to a *multi*-vault backup in
        /// particular — the ZIP is assembled from whatever landed in the
        /// directory, so skipping one quietly ships a backup that is missing a
        /// vault and looks complete.
        case vaultFileNotProduced(vaultName: String)
        /// A file was produced but the exporter could not be built from it.
        case exportFileNotProduced
    }

    /// One place for the three export entry points to fail in.
    ///
    /// They each used a bare `try?`, which was survivable while the only errors
    /// were serialization ones. Reading a key share can now throw — the passcode
    /// seals them, and a locked app cannot open them — so the export gained a
    /// failure mode where the user taps the button and *nothing happens at all*:
    /// no file, no alert, no log. The error is now reported, and the message says
    /// the thing worth saying, which is that the app has to be unlocked.
    private func backupFileReportingFailure(
        _ backupType: VaultBackupType,
        encryptionPassword: String?
    ) async -> FileExporterModel<EncryptedDataFile>? {
        do {
            // `createBackupFile` reports some failures by returning `nil` rather
            // than throwing, and those were falling straight through this
            // handler back to a silent no-op — the exact shape being fixed here.
            guard let exporter = try await createBackupFile(
                backupType,
                encryptionPassword: encryptionPassword
            ) else {
                throw BackupError.exportFileNotProduced
            }
            return exporter
        } catch {
            logger.error("Vault export failed: \(String(describing: error), privacy: .public)")
            // The alert `VaultBackupContainerView` already presents, and it
            // localizes the title itself — so this is the key, not the string.
            alertTitle = "vaultBackupExportFailed"
            showAlert = true
            return nil
        }
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

        return await backupFileReportingFailure(backupType, encryptionPassword: vaultPassword)
    }

    func exportFileWithCustomPassword(_ backupType: VaultBackupType) async -> FileExporterModel<EncryptedDataFile>? {
        return await backupFileReportingFailure(backupType, encryptionPassword: encryptionPassword)
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
            // The result is checked rather than discarded. The ZIP below is
            // built from whatever is in the directory, so a vault that failed to
            // generate would simply not be in it — and the user would be handed
            // a backup that opens, restores, and is missing a wallet.
            guard try await generateBackupFile(
                vault: vault,
                encryptionPassword: encryptionPassword,
                targetDirectory: tempDir
            ) != nil else {
                throw BackupError.vaultFileNotProduced(vaultName: vault.name)
            }
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
        let vsVault = try vault.mapToProtobuff()
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
    ///
    /// Whatever the format, the result is validated before it is offered to the
    /// user: a backup carrying a share this device cannot open is refused at the
    /// point it is read rather than after a vault picker.
    private func decodeVaultFromData(_ data: Data) throws -> Vault? {
        guard let vault = decodeVaultInAnyFormat(data) else { return nil }
        try importer.validate(vault)
        return vault
    }

    private func decodeVaultInAnyFormat(_ data: Data) -> Vault? {
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
                    try importer.validate(vault)
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
        do {
            let results = try importVaults(multipleVaultsToImport, to: modelContext, existing: vaults)
            selectedVault = results.imported.first
            showImportResults(results)
        } catch {
            logger.error("fail to restore vaults: \(error.localizedDescription, privacy: .public)")
            showError("vaultRestoreFailed")
        }
        cleanup()
    }

    private func importVaults(_ vaultsToImport: [Vault], to modelContext: ModelContext, existing: [Vault]) throws -> ImportResults {
        var imported: [Vault] = []
        var replacing: [Vault] = []
        var duplicates = 0
        var skippedNames: [String] = []
        var unsafeNames: [String] = []

        for vault in vaultsToImport {
            // `imported` carries the already-resolved names, so a batch that
            // contains two vaults called "Savings" disambiguates the second
            // against the first rather than upserting it. It also means a second
            // copy of the *same* vault in one ZIP now collides with the first
            // copy as well as with the orphan, so it is skipped as a duplicate
            // rather than asking to replace a row that is already being
            // replaced.
            let plan = insertIfSafe(vault, existing: existing + imported)
            switch plan.decision {
            case .insert:
                imported.append(vault)
            case .replaceOrphaned where plan.replacing.contains(where: { orphan in
                replacing.contains { $0 === orphan }
            }):
                // One incoming vault per orphan. An ordinary second copy of the
                // same vault already collides with the first through
                // `existing + imported` — but two *incomplete* backups can each
                // match a different public key of the same orphan without
                // matching each other, and one row replaced by two vaults is
                // not a replacement.
                unsafeNames.append(vault.name)
                logger.error("Refused a vault during zip import: another vault in this zip already replaces the same stored vault")
            case .replaceOrphaned:
                imported.append(vault)
                replacing.append(contentsOf: plan.replacing)
                logger.info("A vault in this zip replaces a stored one whose key shares can no longer be opened")
            case .duplicate:
                duplicates += 1
                skippedNames.append(vault.name)
                logger.info("Skipped duplicate vault during zip import: \(vault.name)")
            case .unsafeCollision:
                unsafeNames.append(vault.name)
                logger.error("Refused a vault during zip import: storing it would have overwritten a vault already on this device")
            }
        }

        // One lease, one save, for the whole batch: a partial import would leave
        // some vaults on one side of the passcode invariant and some on the other.
        // Default coins are added inside it, because they insert rows of their
        // own and doing that first strands them when the import is refused.
        let coinService = VaultDefaultCoinService(context: modelContext)
        try importer.commit(imported, replacing: replacing, into: modelContext) { vault in
            coinService.setDefaultCoinsOnce(vault: vault)
        }
        // Outside the commit, because the commit is what stores the rows that
        // discovery goes on to write against.
        coinService.startTokenDiscovery()

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

            let plan = insertIfSafe(vault, existing: vaults)
            switch plan.decision {
            case .insert, .replaceOrphaned:
                let coinService = VaultDefaultCoinService(context: modelContext)
                try importer.commit([vault], replacing: plan.replacing, into: modelContext) { vault in
                    coinService.setDefaultCoinsOnce(vault: vault)
                }
                // Outside the commit, because the commit is what stores the rows
                // that discovery goes on to write against.
                coinService.startTokenDiscovery()
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

        // Decoding and storing are separated deliberately. The fallback below
        // exists for a *format* that the new decoder cannot read; letting a
        // failed store fall into it would re-attempt the same bytes as a
        // different format and report the wrong reason for the failure.
        let decoder = JSONDecoder()
        let decoded: Vault
        do {
            // if version get updated , then we can process the migration here
            decoded = try decoder.decode(BackupVault.self, from: vaultData).vault
        } catch {
            logger.warning("failed to import with new format , fallback to the old format instead. \(error.localizedDescription, privacy: .public)")

            // fallback
            do {
                decoded = try decoder.decode(Vault.self, from: vaultData)
            } catch {
                logger.error("fail to restore vault: \(error.localizedDescription)")
                alertTitle = "vaultRestoreFailed"
                showAlert = true
                isVaultImported = false
                return
            }
        }

        let plan = insertIfSafe(decoded, existing: vaults)
        switch plan.decision {
        case .duplicate:
            showError("vaultAlreadyExists")
            return
        case .unsafeCollision:
            showError("vaultImportWouldOverwriteExisting")
            return
        case .insert, .replaceOrphaned:
            break
        }

        do {
            let coinService = VaultDefaultCoinService(context: modelContext)
            try importer.commit([decoded], replacing: plan.replacing, into: modelContext) { vault in
                coinService.setDefaultCoinsOnce(vault: vault)
            }
            // Outside the commit, because the commit is what stores the rows
            // that discovery goes on to write against.
            coinService.startTokenDiscovery()
            selectedVault = decoded
            showAlert = false
            isVaultImported = true
        } catch {
            logger.error("fail to restore vault: \(error.localizedDescription)")
            alertTitle = "vaultRestoreFailed"
            showAlert = true
            isVaultImported = false
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
    /// is refused by ``collides(_:named:with:)``, which restates the raw index
    /// semantics rather than reusing the duplicate rule.
    ///
    /// A vault this device can no longer open is the one exception, and it is a
    /// narrow one: see ``orphanedVault(collidingWith:in:)``. Even then the
    /// collision check still runs — against everything the replacement is *not*
    /// displacing.
    func importDecision(for backupVault: Vault, existing: [Vault]) -> VaultImportDecision {
        plan(for: backupVault, existing: existing).decision
    }

    /// The decision, plus the stored row it displaces.
    ///
    /// The row is resolved here rather than carried on ``VaultImportDecision``
    /// so that decision stays a plain value the tests can compare — a live
    /// `@Model` travelling through one would make it neither comparable nor
    /// safe to hold.
    private struct ImportPlan {
        let decision: VaultImportDecision
        /// At most one, and only ever a vault this device can no longer open.
        /// ``ProtectedVaultImporter/commit(_:replacing:into:prepare:)`` deletes
        /// it in the same save that stores the replacement.
        let replacing: [Vault]
    }

    private func plan(for backupVault: Vault, existing: [Vault]) -> ImportPlan {
        guard isVaultUnique(backupVault: backupVault, vaults: existing) else {
            guard let orphaned = orphanedVault(collidingWith: backupVault, in: existing) else {
                return ImportPlan(decision: .duplicate, replacing: [])
            }

            // The row being replaced is on its way out, so its name is not taken
            // — otherwise every recovery would come back as "Main (2)". It is
            // the *only* row a replacement excuses, though: everything else on
            // the device still has to survive the insert.
            let others = existing.filter { $0 !== orphaned }
            let name = availableVaultName(basedOn: backupVault.name, taken: Set(others.map(\.name)))
            guard !collides(backupVault, named: name, with: others) else {
                return ImportPlan(decision: .unsafeCollision, replacing: [])
            }

            return ImportPlan(decision: .replaceOrphaned(name: name), replacing: [orphaned])
        }

        let name = availableVaultName(basedOn: backupVault.name, taken: Set(existing.map(\.name)))
        guard !collides(backupVault, named: name, with: existing) else {
            return ImportPlan(decision: .unsafeCollision, replacing: [])
        }

        return ImportPlan(decision: .insert(name: name), replacing: [])
    }

    /// The raw `@Attribute(.unique)` index semantics — one clause per unique
    /// field on `Vault` — rather than the duplicate rule, whose empty/`nil`
    /// tolerance is exactly what would let a collision through.
    ///
    /// It is asked on the replacement path too. There it is defence in depth
    /// rather than the load-bearing guard — a replacement already has to declare
    /// every identity the row it displaces holds, which is what keeps an
    /// incomplete backup from matching the orphan on the one key it carries and
    /// upserting over a **healthy** vault on an empty one. Deleting the orphan
    /// would do nothing about that, so both checks stay.
    ///
    /// This is the single place to extend when a unique attribute is added.
    private func collides(_ backupVault: Vault, named name: String, with existing: [Vault]) -> Bool {
        existing.contains { vault in
            vault.name == name
                || vault.pubKeyECDSA == backupVault.pubKeyECDSA
                || vault.pubKeyEdDSA == backupVault.pubKeyEdDSA
                || (vault.publicKeyMLDSA44 != nil && vault.publicKeyMLDSA44 == backupVault.publicKeyMLDSA44)
        }
    }

    /// The one stored vault an incoming backup is allowed to replace.
    ///
    /// This deliberately re-enables, in one tightly bounded path, the
    /// replacement the import gate was hardened against — so every clause below
    /// is the difference between a recovery and a loss, and none of them is a
    /// convenience.
    ///
    /// - **Exactly one colliding vault.** A backup that matches two stored
    ///   vaults is a question this cannot answer, and answering it by picking
    ///   one destroys the other's key material.
    /// - **The wrapper is *confirmed* absent.** `.unavailable` must not qualify:
    ///   a Keychain that merely went quiet may well still hold the key, and the
    ///   shares would open again on the next launch. Deleting a working vault
    ///   over a momentary read failure is the one mistake available here that
    ///   destroys something.
    /// - **Every share sealed, and at least one.** A vault with no shares has
    ///   nothing to be orphaned about. A partly-sealed one is not a state this
    ///   app can produce — the sweep is all-or-nothing — so it is a state to
    ///   refuse rather than to guess about.
    /// - **The backup *is* the stored vault, not merely overlapping with it.**
    ///   Matching on one public key is what makes something a duplicate; it is
    ///   not enough to make it a replacement. Every signing identity the stored
    ///   row carries has to be declared identically by the backup, or the
    ///   replacement drops key material — a file naming a different EdDSA key
    ///   would swap a vault that cannot sign for one that still cannot, and the
    ///   ciphertext that was there would be gone. An identity the *backup* adds
    ///   is fine; one it leaves out is not.
    /// - **The backup carries a share for every key — its own and the stored
    ///   row's.** `ProtectedVaultImporter` proves that whatever the backup does
    ///   carry opens here, and it proves it before the deletion, but a file
    ///   carrying an empty `keyshares` array normalizes perfectly well and would
    ///   buy the deletion with nothing.
    ///
    /// What is deliberately *not* done: nothing here parses a share to confirm
    /// its bytes really derive the public key it is labelled with. That is TSS
    /// work behind a critical boundary, and the ordinary import path extends a
    /// backup the same trust. The checks above are what keep this path from
    /// extending it any *further* than that one does.
    func orphanedVault(collidingWith backupVault: Vault, in existing: [Vault]) -> Vault? {
        let colliding = existing.filter { !isVaultUnique(backupVault: backupVault, vaults: [$0]) }
        guard colliding.count == 1, let stored = colliding.first else { return nil }

        guard case .absent = keyStore.loadWrappedDataKey() else { return nil }

        guard !stored.keyshares.isEmpty,
              stored.keyshares.allSatisfy({ protector.isSealed($0.keyshare) }) else {
            return nil
        }

        guard preserves(stored.pubKeyECDSA, in: backupVault.pubKeyECDSA),
              preserves(stored.pubKeyEdDSA, in: backupVault.pubKeyEdDSA),
              preserves(stored.publicKeyMLDSA44, in: backupVault.publicKeyMLDSA44) else {
            return nil
        }

        let carried = Set(backupVault.keyshares.map(\.pubkey))
        let declared = Set(
            [backupVault.pubKeyECDSA, backupVault.pubKeyEdDSA, backupVault.publicKeyMLDSA44 ?? ""]
                .compactMap(\.nilIfEmpty)
        )
        guard !backupVault.keyshares.isEmpty,
              backupVault.keyshares.allSatisfy({ !$0.keyshare.isEmpty }),
              carried.isSuperset(of: declared),
              carried.isSuperset(of: Set(stored.keyshares.map(\.pubkey))) else {
            return nil
        }

        return stored
    }

    /// Whether a signing identity the stored vault holds survives the
    /// replacement unchanged.
    ///
    /// An identity the stored row does not have is nothing to preserve. One it
    /// has and the backup does not — or declares differently — is key material
    /// the replacement would take away with the row.
    private func preserves(_ stored: String?, in backup: String?) -> Bool {
        guard let stored = stored?.nilIfEmpty else { return true }
        return stored == backup?.nilIfEmpty
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

    /// Runs the import gate and renames `vault` to an available name when it is
    /// safe to store. Returns the plan so the caller can surface the outcome and
    /// hand the displaced row on. Storage itself never happens here: it must go
    /// through ``ProtectedVaultImporter/commit(_:replacing:into:prepare:)``,
    /// which normalizes, deletes, inserts and saves inside a single
    /// passcode-transition-safe lease — a direct `modelContext.insert` here
    /// would land outside that lease, and a direct `delete` outside the save
    /// that justifies it.
    private func insertIfSafe(_ vault: Vault, existing: [Vault]) -> ImportPlan {
        let plan = plan(for: vault, existing: existing)

        switch plan.decision {
        case .insert(let name), .replaceOrphaned(let name):
            if vault.name != name {
                logger.info("Renamed an imported vault to avoid colliding with a stored vault's name")
                vault.name = name
            }
        case .duplicate, .unsafeCollision:
            break
        }

        return plan
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

        guard let rootViewController = UIApplication.shared.activeContentWindow?.rootViewController else {
            // Nothing to present into, so the import stalls here rather than
            // finding somewhere else to put a password field — the window the
            // app raises over its content while locked is not a fallback.
            logger.error("No content window to present the backup password prompt in")
            return
        }
        rootViewController.present(alert, animated: true, completion: nil)
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

        guard let rootViewController = UIApplication.shared.activeContentWindow?.rootViewController else {
            // Nothing to present into, so the import stalls here rather than
            // finding somewhere else to put a password field — the window the
            // app raises over its content while locked is not a fallback.
            logger.error("No content window to present the backup password prompt in")
            return
        }
        rootViewController.present(alert, animated: true, completion: nil)
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
