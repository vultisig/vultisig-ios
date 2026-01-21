//
//  EncryptedDataFile.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-13.
//

import SwiftUI
import UniformTypeIdentifiers

struct EncryptedDataFile: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init?(url: URL?) {
        guard let url = url, let data = try? Data(contentsOf: url) else { return nil }
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}
