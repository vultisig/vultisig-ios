//
//  FileManagerExtension.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-20.
//

import SwiftUI
import Foundation
import ZIPFoundation
import OSLog

extension FileManager {
    func clearTmpDirectory() {
        do {
            let tmpDirectory = try contentsOfDirectory(atPath: NSTemporaryDirectory())
            try tmpDirectory.forEach {[unowned self] file in
                let path = String.init(format: "%@%@", NSTemporaryDirectory(), file)
                try self.removeItem(atPath: path)
            }
        } catch {
            print(error)
        }
    }

    /// Extract a ZIP file to a destination directory using ZIPFoundation
    /// - Important: Protects against zip-slip attacks and denies symlink extraction
    func unzipItem(at sourceURL: URL, to destinationURL: URL) throws {
        let logger = Logger(subsystem: "com.vultisig.wallet", category: "zip-extraction")

        guard let archive = try? Archive(url: sourceURL, accessMode: .read, pathEncoding: nil) else {
            logger.error("Failed to open ZIP archive at: \(sourceURL.path, privacy: .public)")
            throw ZipFileError.failedToExtractZIP("Failed to open ZIP archive")
        }

        let destinationRoot = destinationURL.standardizedFileURL

        for entry in archive {
            // Security: Deny symlinks entirely to prevent escaping via link targets
            guard entry.type != .symlink else {
                logger.warning("Skipping symlink entry: \(entry.path, privacy: .public)")
                continue
            }

            // Security: Sanitize path to prevent zip-slip attacks
            let unsafeDestination = destinationURL.appendingPathComponent(entry.path)
            let resolvedDestination = unsafeDestination.standardizedFileURL

            // Verify the resolved path stays within the destination directory
            let rootPath = destinationRoot.path
            let targetPath = resolvedDestination.path
            let isWithinRoot = targetPath == rootPath || targetPath.hasPrefix(rootPath + "/")

            guard isWithinRoot else {
                logger.error("Blocked path traversal attempt for entry: \(entry.path, privacy: .public)")
                continue
            }

            // Create parent directory only after security verification
            let parentDir = resolvedDestination.deletingLastPathComponent()
            if !fileExists(atPath: parentDir.path) {
                try createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            // Skip directory entries (already created via parent dir logic)
            guard entry.type == .file else {
                continue
            }

            // Extract the file
            do {
                _ = try archive.extract(entry, to: resolvedDestination)
            } catch {
                logger.error("Failed to extract entry \(entry.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
