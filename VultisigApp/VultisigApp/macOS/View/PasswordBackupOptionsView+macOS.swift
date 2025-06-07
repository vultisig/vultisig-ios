//
//  PasswordBackupOptionsView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-21.
//

#if os(macOS)
import SwiftUI

extension PasswordBackupOptionsView {
    var content: some View {
        VStack(spacing: 36) {
            header
            Spacer()
            
            VStack(spacing: 36) {
                icon
                textContent
                buttons
            }
            .padding(24)
            
            Spacer()
        }
    }
    
    var header: some View {
        GeneralMacHeader(title: "")
    }
    
    var withoutPasswordButton: some View {
        Button {
            showSkipShareSheet = true
        } label: {
            withoutPasswordLabel
        }
        .fileExporter(
            isPresented: $showSkipShareSheet,
            document: EncryptedDataFile(url: backupViewModel.encryptedFileURLWithoutPassowrd),
            contentType: .data,
            defaultFilename: "\(vault.getExportName())"
        ) { result in
            switch result {
            case .success(let url):
                print("File saved to: \(url)")
                fileSaved()
                dismissView()
            case .failure(let error):
                print("Error saving file: \(error.localizedDescription)")
                backupViewModel.alertTitle = "errorSavingFile"
                backupViewModel.showAlert = true
            }
        }
    }
}
#endif
