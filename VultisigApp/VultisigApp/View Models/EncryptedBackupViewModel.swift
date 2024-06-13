//
//  EncryptedBackupViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-13.
//

import Foundation
import CryptoKit

class EncryptedBackupViewModel: ObservableObject {
    @Published var showVaultExporter = false
    @Published var showVaultImporter = false
    @Published var encryptedFileURL: URL?
    @Published var decryptedContent: String = ""
    @Published var encryptionPassword: String = ""
    @Published var decryptionPassword: String = ""
    
    @Published var showAlert: Bool = false
    @Published var alertMessage: String = ""
    
    enum VultisigDocumentError : Error{
        case customError(String)
    }
    
    // Export
    
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
                showVaultExporter = true
            } catch {
                print("Error writing file: \(error.localizedDescription)")
            }
        } catch {
            print(error)
        }
    }
    
    private func encrypt(data: Data, password: String) -> Data? {
        let key = SymmetricKey(data: SHA256.hash(data: Data(password.utf8)))
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            return sealedBox.combined
        } catch {
            print("Error encrypting data: \(error.localizedDescription)")
            return nil
        }
    }
}
