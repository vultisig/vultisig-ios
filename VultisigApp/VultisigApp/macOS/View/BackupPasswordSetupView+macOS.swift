//
//  BackupPasswordSetupView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(macOS)
import SwiftUI

extension BackupPasswordSetupView {
    var content: some View {
        ZStack {
            Background()
            main
        }
    }
    
    var main: some View {
        VStack {
            headerMac
            view
        }
        .navigationDestination(isPresented: $navigationLinkActive) {
            HomeView(selectedVault: vault, showVaultsList: false, shouldJoinKeygen: false)
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "backup")
    }
    
    var view: some View {
        VStack {
            passwordField
            Spacer()
            disclaimer
            buttons
        }
        .padding(.horizontal, 25)
    }
    
    var saveButton: some View {
        Button(action: {
            handleProxyTap()
        }) {
            FilledButton(title: "save")
        }
        .fileExporter(
            isPresented: $showSaveShareSheet,
            document: EncryptedDataFile(url: backupViewModel.encryptedFileURLWithPassowrd),
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
                backupViewModel.alertMessage = error.localizedDescription
                backupViewModel.showAlert = true
            }
        }
    }
    
    var skipButton: some View {
        Button(action: {
            showSkipShareSheet = true
        }) {
            OutlineButton(title: "skip")
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
                backupViewModel.alertMessage = error.localizedDescription
                backupViewModel.showAlert = true
            }
        }
    }
}
#endif
