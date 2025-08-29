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
        var coordinatorError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: directoryURL,
            options: .forUploading,
            error: &coordinatorError
        ) { zipCreatedURL in
            do {
                // will fail if file already exists at finalURL
                // use `replaceItem` instead if you want "overwrite" behavior
                try FileManager.default.moveItem(at: zipCreatedURL, to: zipFinalURL)
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
