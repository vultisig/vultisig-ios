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
    
    @StateObject var backupViewModel = EncryptedBackupViewModel()
    @State var show = false
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        content
            .navigationBarBackButtonHidden(true)
            .navigationTitle(NSLocalizedString("backup", comment: "Backup"))
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
            .fileExporter(isPresented: $backupViewModel.showVaultExporter,
                          document: EncryptedDataFile(url: backupViewModel.encryptedFileURLWithPassowrd),
                          contentType: .data,
                          defaultFilename: "\(vault.getExportName())"
            ) { result in
                switch result {
                case .success(let url):
                    print("File saved to: \(url)")
                    fileSaved()
                    dismiss()
                case .failure(let error):
                    print("Error saving file: \(error.localizedDescription)")
                    backupViewModel.alertTitle = "errorSavingFile"
                    backupViewModel.alertMessage = error.localizedDescription
                    backupViewModel.showAlert = true
                }
                
            }
    }
    
    var content: some View {
        ZStack {
            Background()
            view
        }
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
        }
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
        ZStack {
            if backupViewModel.encryptionPassword.isEmpty && verifyPassword.isEmpty {
                proxySaveButton
            } else if backupViewModel.encryptionPassword != verifyPassword {
                proxySaveButton
            } else {
                if let fileURL = backupViewModel.encryptedFileURLWithPassowrd {
                    #if os(iOS)
                    ShareLink(item: fileURL) {
                        FilledButton(title: "save")
                    }
                    .simultaneousGesture(TapGesture().onEnded() {
                        fileSaved()
                    })
                    #elseif  os(macOS)
                    Button{
                        backupViewModel.showVaultExporter = true
                    } label: {
                        FilledButton(title: "save")
                    }
                    
                    #endif
                }
            }
        }
    }
    
    var skipButton: some View {
        ZStack {
            if let fileURL = backupViewModel.encryptedFileURLWithoutPassowrd {
                #if os(iOS)
                ShareLink(item: fileURL) {
                    OutlineButton(title: "skip")
                }
                .simultaneousGesture(TapGesture().onEnded() {
                    print("set file saved")
                    fileSaved()
                })
                #elseif os(macOS)
                Button{
                    backupViewModel.showVaultExporter = true
                } label: {
                    OutlineButton(title: "skip")
                }
                #endif
            }
        }
    }
    
    var proxySaveButton: some View {
        Button {
            handleProxyTap()
        } label: {
            FilledButton(title: "save")
        }
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
    }
    
    private func export() {
        backupViewModel.exportFile(vault)
    }
    
    private func fileSaved() {
        vault.isBackedUp = true
    }
    
}

#Preview {
    BackupPasswordSetupView(vault: Vault.example)
}
