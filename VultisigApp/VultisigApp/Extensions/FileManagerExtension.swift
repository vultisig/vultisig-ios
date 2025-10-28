//
//  FileManagerExtension.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-20.
//

import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif
import ZIPFoundation

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
    func unzipItem(at sourceURL: URL, to destinationURL: URL) throws {
        print("📦 Attempting to extract ZIP file via ZIPFoundation")
        print("  Source: \(sourceURL.lastPathComponent)")
        print("  Destination: \(destinationURL.path)")

        guard let archive = Archive(url: sourceURL, accessMode: .read) else {
            throw ZipFileError.failedToExtractZIP("Failed to open ZIP archive")
        }

        for entry in archive {
            let entryDestinationURL = destinationURL.appendingPathComponent(entry.path)
            let parentDir = entryDestinationURL.deletingLastPathComponent()
            if !fileExists(atPath: parentDir.path) {
                try createDirectory(at: parentDir, withIntermediateDirectories: true)
            }
            do {
                try archive.extract(entry, to: entryDestinationURL)
                print("  📄 Extracted: \(entry.path)")
            } catch {
                print("  ⚠️ Failed to extract \(entry.path): \(error)")
            }
        }
    }
}
