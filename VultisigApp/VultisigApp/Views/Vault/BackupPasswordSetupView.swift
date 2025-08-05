//
//  BackupPasswordSetupView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-13.
//

import SwiftUI

struct BackupPasswordSetupView: View {
    let tssType: TssType
    let vault: Vault
    var isNewVault = false
    
    @State var verifyPassword: String = ""
    @State var navigationLinkActive = false
    @State var homeLinkActive = false
    
    @StateObject var backupViewModel = EncryptedBackupViewModel()
    @State var showSkipShareSheet = false
    @State var showSaveShareSheet = false
    @State var activityItems: [Any] = []
    @State var passwordErrorMessage: String = ""
    @State var passwordVerifyErrorMessage: String = ""
    @FocusState var passwordFieldFocused
    @FocusState var passwordVerifyFieldFocused
    
    var body: some View {
        ZStack {
            mainContent
        }
        .sensoryFeedback(.success, trigger: vault.isBackedUp)
        .onAppear(){
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                passwordFieldFocused = true
            }
        }
    }
    
    var mainContent: some View {
        content
            .onAppear {
                backupViewModel.resetData()
            }
            .onDisappear {
                backupViewModel.resetData()
            }
            .onChange(of: verifyPassword) { oldValue, newValue in
                if backupViewModel.encryptionPassword == verifyPassword {
                    passwordErrorMessage = ""
                    passwordVerifyErrorMessage = ""
                    handleSaveTap()
                }
            }
    }
    
    var passwordField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("optionalPasswordProtectBackup", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textPrimary)
            
            textfield
            verifyTextfield
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
    }
    
    var textfield: some View {
        HiddenTextField(placeholder: "enterPassword",
                        password: $backupViewModel.encryptionPassword,
                        errorMessage: passwordErrorMessage)
            .padding(.top, 8)
            .focused($passwordFieldFocused)
            .onSubmit {
                if !backupViewModel.encryptionPassword.isEmpty {
                    passwordVerifyFieldFocused = true
                }
            }
    }
    
    var verifyTextfield: some View {
        HiddenTextField(placeholder: "verifyPassword", password: $verifyPassword, errorMessage: passwordVerifyErrorMessage)
            .focused($passwordVerifyFieldFocused)
            .onSubmit {
                handleProxyTap()
            }
            
    }
    
    var disclaimer: some View {
        OutlinedDisclaimer(text: NSLocalizedString("backupPasswordDisclaimer", comment: ""))
            .padding(.horizontal, 16)
    }
    
    var buttons: some View {
        VStack(spacing: 20) {
            saveButton
        }
        .padding(.top, 16)
        .padding(.bottom, 40)
        .padding(.horizontal, 16)
    }
    
    private func handleSaveTap() {
        export()
    }
    
    func handleProxyTap() {
        guard !backupViewModel.encryptionPassword.isEmpty else {
            passwordErrorMessage = NSLocalizedString("emptyField", comment: "")
            return
        }
        passwordErrorMessage = ""
        guard !verifyPassword.isEmpty else {
            passwordVerifyErrorMessage = NSLocalizedString("emptyField", comment: "")
            return
        }
        passwordVerifyErrorMessage = ""
        guard backupViewModel.encryptionPassword == verifyPassword else {
            passwordErrorMessage = NSLocalizedString("passwordMismatch", comment: "")
            passwordVerifyErrorMessage = NSLocalizedString("passwordMismatch", comment: "")
            return
        }
        passwordErrorMessage = ""
        passwordVerifyErrorMessage = ""
        showSaveShareSheet = true
    }
    
    func export() {
        backupViewModel.exportFile(vault)
    }
    
    func fileSaved() {
        vault.isBackedUp = true
        FileManager.default.clearTmpDirectory()
    }
    
    func dismissView() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if isNewVault {
                navigationLinkActive = true
            } else {
                homeLinkActive = true
            }
        }
    }
}

#Preview {
    BackupPasswordSetupView(tssType: .Keygen, vault: Vault.example)
}
