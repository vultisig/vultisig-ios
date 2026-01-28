//
//  VULTFileDocument.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-20.
//

import SwiftUI
import UniformTypeIdentifiers

struct VULTFileDocument: FileDocument {
    // Change content to Result<[URL], Error>
    var content: Result<[URL], Error>

    // Specify the supported UTI
    static var readableContentTypes: [UTType] {
        [.vaultFile]
    }

    // Custom initializer for creating new documents (no URLs at this point, just an empty success)
    init(content: Result<[URL], Error> = .success([])) {
        self.content = content
    }

    // Required initializer to load an existing document
    init(configuration: ReadConfiguration) throws {

        // Attempt to load URLs from the file's contents (e.g., paths stored in the file)
        if let data = configuration.file.regularFileContents,
           let contentString = String(data: data, encoding: .utf8) {
            // Convert the string data back into URLs (assuming they were saved as strings)
            let urls = contentString
                .split(separator: "\n")
                .compactMap { URL(string: String($0)) }

            // Set the content to the URLs
            self.content = .success(urls)
        } else {
            // If no data was found, throw an error
            self.content = .failure(CocoaError(.fileReadCorruptFile))
        }

    }

    // Required function to save the document content
    // swiftlint:disable:next unused_parameter
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Get the URLs from the result, if it's a success
        switch content {
        case .success(let urls):
            // Convert the URLs to a newline-separated string to store in the file
            let urlStrings = urls.map { $0.absoluteString }.joined(separator: "\n")
            let data = urlStrings.data(using: .utf8) ?? Data()
            return FileWrapper(regularFileWithContents: data)

        case .failure:
            // In case of an error, return empty data or handle accordingly
            return FileWrapper(regularFileWithContents: Data())
        }
    }
}
