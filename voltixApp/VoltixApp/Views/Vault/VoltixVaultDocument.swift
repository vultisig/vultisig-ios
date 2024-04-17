//
//  VoltixVaultDocument.swift
//  VoltixApp
//


import Foundation
import UniformTypeIdentifiers
import SwiftUI

struct VoltixDocument: FileDocument {
    enum VoltixDocumentError : Error{
        case customError(String)
    }
    static var readableContentTypes: [UTType] { [.data] }
    var backupVault: BackupVault?
    init(vault: BackupVault? = nil) {
        self.backupVault = vault
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let hexEncodedData = configuration.file.regularFileContents else {
            throw VoltixDocumentError.customError("Could not read file")
        }
        guard let hexString = String(data: hexEncodedData, encoding: .utf8) else {
            throw VoltixDocumentError.customError("Could not convert data to string")
        }
        let decodedData = Data(hexString: hexString)
        backupVault = try JSONDecoder().decode(BackupVault.self, from: decodedData!)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let vault = backupVault else {
            throw VoltixDocumentError.customError("No vault to save")
        }
        let data = try JSONEncoder().encode(vault)
        guard let hexData = data.hexString.data(using: .utf8) else {
            throw VoltixDocumentError.customError("Could not convert data to hex")
        }
        return FileWrapper(regularFileWithContents: hexData)
    }
}
