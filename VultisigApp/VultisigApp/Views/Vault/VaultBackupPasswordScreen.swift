//
//  VaultBackupPasswordScreen.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-13.
//

import SwiftUI

struct VaultBackupPasswordScreen: View {
    let tssType: TssType
    let vault: Vault
    var isNewVault = false
    
    @State var verifyPassword: String = ""
    @State var presentSuccess = false
    @State var presentHome = false
    
    @StateObject var backupViewModel = EncryptedBackupViewModel()
    @State var presentFileExporter = false
    @State var fileModel: FileExporterModel?
    @State var activityItems: [Any] = []
    @State var passwordErrorMessage: String = ""
    @State var passwordVerifyErrorMessage: String = ""
    @FocusState var passwordFieldFocused
    @FocusState var passwordVerifyFieldFocused
    
    var body: some View {
        Screen(title: "backup".localized) {
            VStack {
                passwordField
                Spacer()
                VStack(spacing: 16) {
                    disclaimer
                    saveButton
                }
            }
        }
        .sensoryFeedback(.success, trigger: vault.isBackedUp)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                passwordFieldFocused = true
            }
            
            backupViewModel.resetData()
        }
        .onDisappear {
            backupViewModel.resetData()
        }
        .onChange(of: verifyPassword) { oldValue, newValue in
            if backupViewModel.encryptionPassword == verifyPassword {
                passwordErrorMessage = ""
                passwordVerifyErrorMessage = ""
            }
        }
        .navigationDestination(isPresented: $presentSuccess) {
            BackupVaultSuccessView(tssType: tssType, vault: vault)
        }
        .navigationDestination(isPresented: $presentHome) {
            HomeView(selectedVault: vault)
        }
        .fileExporter(isPresented: $presentFileExporter, fileModel: $fileModel) { result in
            switch result {
            case .success(let didSave):
                if didSave {
                    fileSaved()
                    dismissView()
                }
            case .failure(let error):
                print("Error saving file: \(error.localizedDescription)")
                backupViewModel.alertTitle = "errorSavingFile"
                backupViewModel.showAlert = true
            }
        }
    }
    
    @ViewBuilder
    var saveButton: some View {
        PrimaryButton(title: "save") {
            onSave()
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
                onSave()
            }
    }
    
    var disclaimer: some View {
        OutlinedDisclaimer(text: NSLocalizedString("backupPasswordDisclaimer", comment: ""))
    }

    func onSave() {
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
        
        guard let fileModel = backupViewModel.exportFileWithCustomPassword(vault) else {
            return
        }
        
        self.fileModel = fileModel
        presentFileExporter = true
    }
    
    func fileSaved() {
        vault.isBackedUp = true
        FileManager.default.clearTmpDirectory()
    }
    
    func dismissView() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if isNewVault {
                presentSuccess = true
            } else {
                presentHome = true
            }
        }
    }
}

#Preview {
    VaultBackupPasswordScreen(tssType: .Keygen, vault: Vault.example)
}
