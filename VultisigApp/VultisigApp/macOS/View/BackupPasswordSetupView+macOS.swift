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
            BackupVaultSuccessView(tssType: tssType, vault: vault)
        }
        .navigationDestination(isPresented: $homeLinkActive) {
            HomeView(selectedVault: vault)
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
        PrimaryButton(title: "save") {
            handleProxyTap()
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
                backupViewModel.showAlert = true
            }
        }
    }
    
    var skipButton: some View {
        PrimaryButton(title: "skipPassword", type: .secondary) {
            showSkipShareSheet = true
        }
        .fileExporter(
            isPresented: $showSkipShareSheet,
            document: EncryptedDataFile(url: backupViewModel.encryptedFileURLWithoutPassword),
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
