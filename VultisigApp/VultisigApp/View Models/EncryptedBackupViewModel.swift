//
//  EncryptedBackupViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-13.
//

import Foundation

class EncryptedBackupViewModel: ObservableObject {
    @Published private var showVaultExporter = false
    @Published private var showVaultImporter = false
    @Published private var encryptedFileURL: URL?
    @Published private var decryptedContent: String = ""
    @Published private var encryptionPassword: String = ""
    @Published private var decryptionPassword: String = ""
    
    func exportFile(_ vault: Vault) {
        do {
            let data = try JSONEncoder().encode(vault)
            guard let hexData = data.hexString.data(using: .utf8) else {
                throw VultisigDocumentError.customError("Could not convert data to hex")
            }
            
            let dataToSave: Data
            if encryptionPassword.isEmpty {
                dataToSave = hexData
            } else if let encryptedData = encrypt(data: hexData, password: encryptionPassword) {
                dataToSave = encryptedData
            } else {
                print("Error encrypting data")
                return
            }
            
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("file.dat")
            do {
                try dataToSave.write(to: tempURL)
                encryptedFileURL = tempURL
                isShowingFileExporter = true
            } catch {
                print("Error writing file: \(error.localizedDescription)")
            }
        } catch {
            print(error)
        }
    }
}
