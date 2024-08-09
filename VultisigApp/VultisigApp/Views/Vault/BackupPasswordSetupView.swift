//
//  BackupPasswordSetupView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-13.
//

import SwiftUI

struct BackupPasswordSetupView: View {
    let vault: Vault
    var isNewVault = false
    
    @State var verifyPassword: String = ""
    @State var navigationLinkActive = false
    @State var alreadyShowingPopup = false
    
    @StateObject var backupViewModel = EncryptedBackupViewModel()
    @State var showSkipShareSheet = false
    @State var showSaveShareSheet = false
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Background()
            main
        }
#if os(iOS)
            .navigationBarBackButtonHidden(true)
            .navigationTitle(NSLocalizedString("backup", comment: "Backup"))
            .toolbar {
                ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                    NavigationBackButton()
                }
            }
#endif
            .alert(isPresented: $backupViewModel.showAlert) {
                alert
            }
            .onAppear {
                backupViewModel.resetData()
                handleSkipTap()
            }
            .onDisappear {
                backupViewModel.resetData()
            }
            .onChange(of: verifyPassword) { oldValue, newValue in
                if backupViewModel.encryptionPassword == verifyPassword {
                    handleSaveTap()
                }
            }
    }
    
    var main: some View {
        VStack {
#if os(macOS)
            headerMac
#endif
            view
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "backup")
    }
    
    var view: some View {
        VStack {
            passwordField
            Spacer()
            buttons
        }
#if os(macOS)
        .padding(.horizontal, 25)
#endif
    }
    
    var passwordField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("optionalPasswordProtectBackup", comment: ""))
                .font(.body14MontserratMedium)
                .foregroundColor(.neutral0)
            
            textfield
            verifyTextfield
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
    }
    
    var textfield: some View {
        HiddenTextField(placeholder: "enterPassword", password: $backupViewModel.encryptionPassword)
            .padding(.top, 8)
    }
    
    var verifyTextfield: some View {
        HiddenTextField(placeholder: "verifyPassword", password: $verifyPassword)
    }
    
    var buttons: some View {
        VStack(spacing: 20) {
            saveButton
            skipButton
        }
        .padding(40)
    }
    
    var saveButton: some View {
        Button(action: {
            handleProxyTap()
        }) {
            FilledButton(title: "save")
        }
#if os(iOS)
        .sheet(isPresented: $showSaveShareSheet, onDismiss: {
            dismissView()
        }) {
            if let fileURL = backupViewModel.encryptedFileURLWithPassowrd {
                ShareSheetViewController(activityItems: [fileURL])
                    .presentationDetents([.medium])
                    .ignoresSafeArea(.all)
            }
        }
#elseif os(macOS)
        .fileExporter(
            isPresented: $showSaveShareSheet,
            document: EncryptedDataFile(url: backupViewModel.encryptedFileURLWithPassowrd),
            contentType: .data,
            defaultFilename: "\(vault.getExportName())"
        ) { result in
            switch result {
            case .success(let url):
                print("File saved to: \(url)")
                dismissView()
            case .failure(let error):
                print("Error saving file: \(error.localizedDescription)")
                backupViewModel.alertTitle = "errorSavingFile"
                backupViewModel.alertMessage = error.localizedDescription
                backupViewModel.showAlert = true
            }
            
        }
#endif
    }
    
    var skipButton: some View {
        Button(action: {
            showSkipShareSheet = true
            fileSaved()
        }) {
            OutlineButton(title: "skip")
        }
#if os(iOS)
        .sheet(isPresented: $showSkipShareSheet, onDismiss: {
            dismissView()
        }) {
            if let fileURL = backupViewModel.encryptedFileURLWithoutPassowrd {
                ShareSheetViewController(activityItems: [fileURL])
                    .presentationDetents([.medium])
                    .ignoresSafeArea(.all)
            }
        }
#elseif os(macOS)
        .fileExporter(
            isPresented: $showSkipShareSheet,
            document: EncryptedDataFile(url: backupViewModel.encryptedFileURLWithoutPassowrd),
            contentType: .data,
            defaultFilename: "\(vault.getExportName())"
        ) { result in
            switch result {
            case .success(let url):
                print("File saved to: \(url)")
                dismissView()
            case .failure(let error):
                print("Error saving file: \(error.localizedDescription)")
                backupViewModel.alertTitle = "errorSavingFile"
                backupViewModel.alertMessage = error.localizedDescription
                backupViewModel.showAlert = true
            }
        }
#endif
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString(backupViewModel.alertTitle, comment: "")),
            message: Text(NSLocalizedString(backupViewModel.alertMessage, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    private func handleSaveTap() {
        export()
    }
    
    private func handleSkipTap() {
        backupViewModel.encryptionPassword = ""
        export()
    }
    
    private func handleProxyTap() {
        guard !backupViewModel.encryptionPassword.isEmpty && !verifyPassword.isEmpty else {
            backupViewModel.alertTitle = "emptyField"
            backupViewModel.alertMessage = "checkEmptyField"
            backupViewModel.showAlert = true
            return
        }
        
        guard backupViewModel.encryptionPassword == verifyPassword else {
            backupViewModel.alertTitle = "passwordMismatch"
            backupViewModel.alertMessage = "verifyPasswordMismatch"
            backupViewModel.showAlert = true
            return
        }
        
        showSaveShareSheet = true
        fileSaved()
    }
    
    private func export() {
        backupViewModel.exportFile(vault)
    }
    
    private func fileSaved() {
        vault.isBackedUp = true
    }
    
    private func dismissView() {
        alreadyShowingPopup = false
        if isNewVault {
            navigationLinkActive = true
        } else {
            dismiss()
        }
    }
}

#Preview {
    BackupPasswordSetupView(vault: Vault.example)
}
