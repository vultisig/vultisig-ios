//
//  PasswordTestView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-12.
//

import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

struct PasswordTestView: View {
    let vault: Vault
    @State private var isShowingFileExporter = false
    @State private var isShowingFileImporter = false
    @State private var encryptedFileURL: URL?
    @State private var decryptedContent: String = ""
    @State private var fileContent: String = "This is the content of the file."
    @State private var encryptionPassword: String = ""
    @State private var decryptionPassword: String = ""

    var body: some View {
        VStack {
            TextField("File Content", text: $fileContent)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            SecureField("Encryption Password (leave blank to skip encryption)", text: $encryptionPassword)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            Button("Export File") {
                exportFile()
            }
            .padding()
            
            Button("Import File") {
                isShowingFileImporter = true
            }
            .padding()
            
            if !decryptedContent.isEmpty {
                Text("Decrypted Content: \(decryptedContent)")
                    .padding()
            }
        }
        .fileExporter(
            isPresented: $isShowingFileExporter,
            document: EncryptedDataFile(url: encryptedFileURL),
            contentType: .data,
            defaultFilename: "file.dat"
        ) { result in
            switch result {
            case .success(let url):
                print("File saved to: \(url)")
            case .failure(let error):
                print("Error saving file: \(error.localizedDescription)")
            }
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    importFile(from: url)
                }
            case .failure(let error):
                print("Error importing file: \(error.localizedDescription)")
            }
        }
    }
    
    enum VultisigDocumentError : Error{
        case customError(String)
    }
    
    func exportFile() {
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
    
    func importFile(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            
            // Try to decrypt with empty password first
            if let decryptedString = decryptOrReadData(data: data, password: "") {
                decryptedContent = decryptedString
            } else {
                // Prompt for password if decryption with empty password fails
                promptForPasswordAndImport(from: url)
            }
        } catch {
            print("Error reading file: \(error.localizedDescription)")
        }
    }
    
    func promptForPasswordAndImport(from url: URL) {
        let alert = UIAlertController(title: "Enter Password", message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.isSecureTextEntry = true
            textField.placeholder = "Password"
        }
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            if let password = alert.textFields?.first?.text {
                decryptionPassword = password
                importFileWithPassword(from: url, password: password)
            }
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        // Find the root view controller and present the alert
        if let rootViewController = UIApplication.shared.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true, completion: nil)
        }
    }
    
    func importFileWithPassword(from url: URL, password: String) {
        do {
            let data = try Data(contentsOf: url)
            if let decryptedData = decrypt(data: data, password: password),
               let decryptedString = String(data: decryptedData, encoding: .utf8) {
                decryptedContent = decryptedString
            } else {
                decryptedContent = "Failed to decrypt the content."
            }
        } catch {
            print("Error reading file: \(error.localizedDescription)")
        }
    }
    
    func decryptOrReadData(data: Data, password: String) -> String? {
        if password.isEmpty {
            // Try to read as plain text
            return String(data: data, encoding: .utf8)
        } else {
            // Try to decrypt
            return decrypt(data: data, password: password).flatMap { String(data: $0, encoding: .utf8) }
        }
    }
    
    func encrypt(data: Data, password: String) -> Data? {
        let key = SymmetricKey(data: SHA256.hash(data: Data(password.utf8)))
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            return sealedBox.combined
        } catch {
            print("Error encrypting data: \(error.localizedDescription)")
            return nil
        }
    }
    
    func decrypt(data: Data, password: String) -> Data? {
        let key = SymmetricKey(data: SHA256.hash(data: Data(password.utf8)))
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return decryptedData
        } catch {
            print("Error decrypting data: \(error.localizedDescription)")
            return nil
        }
    }
}

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
