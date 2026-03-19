//
//  ZipFileGenerator.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 28/08/2025.
//

import Foundation

enum ZipFileError: Error {
    case urlNotADirectory(URL)
    case failedToCreateZIP(Swift.Error)
    case failedToExtractZIP(String)
}

struct ZipFileGenerator {
    func createZip(
        zipFinalURL: URL,
        fromDirectory directoryURL: URL
    ) throws -> URL {
        // see URL extension below
        guard directoryURL.isDirectory else {
            throw ZipFileError.urlNotADirectory(directoryURL)
        }

        var fileManagerError: Swift.Error?
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: zipFinalURL.deletingLastPathComponent(),
                                   withIntermediateDirectories: true,
                                   attributes: nil)
        } catch {
            throw ZipFileError.failedToCreateZIP(error)
        }
        var coordinatorError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: directoryURL,
            options: .forUploading,
            error: &coordinatorError
        ) { zipCreatedURL in
            do {
                if fm.fileExists(atPath: zipFinalURL.path) {
                    try fm.removeItem(at: zipFinalURL)
                }
                try fm.copyItem(at: zipCreatedURL, to: zipFinalURL)
            } catch {
                fileManagerError = error
            }
        }
        if let error = coordinatorError ?? fileManagerError {
            throw ZipFileError.failedToCreateZIP(error)
        }
        return zipFinalURL
    }
}
extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}
