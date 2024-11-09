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
        content
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
    
    var disclaimer: some View {
        OutlinedDisclaimer(text: NSLocalizedString("backupPasswordDisclaimer", comment: ""))
            .padding(.horizontal, 16)
    }
    
    var buttons: some View {
        VStack(spacing: 20) {
            saveButton
            skipButton
        }
        .padding(.top, 16)
        .padding(.bottom, 40)
        .padding(.horizontal, 16)
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
    
    func handleProxyTap() {
        guard !backupViewModel.encryptionPassword.isEmpty else {
            backupViewModel.alertTitle = "useSkipInstead"
            backupViewModel.alertMessage = "useSkipWithoutPasswordMessage"
            backupViewModel.showAlert = true
            return
        }
        
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
    
    func fileSaved() {
        vault.isBackedUp = true
    }
    
    func dismissView() {
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
