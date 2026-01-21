//
//  VaultBackupPasswordScreen.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-13.
//

import SwiftUI

struct VaultBackupPasswordScreen: View {
    let tssType: TssType
    let backupType: VaultBackupType
    var isNewVault = false

    @State var verifyPassword: String = ""

    @StateObject var backupViewModel = EncryptedBackupViewModel()
    @State var presentFileExporter = false
    @State var fileModel: FileExporterModel<EncryptedDataFile>?
    @State var activityItems: [Any] = []
    @State var passwordErrorMessage: String = ""
    @State var passwordVerifyErrorMessage: String = ""
    @FocusState var passwordFieldFocused
    @FocusState var passwordVerifyFieldFocused

    var body: some View {
        VaultBackupContainerView(
            presentFileExporter: $presentFileExporter,
            fileModel: $fileModel,
            backupViewModel: backupViewModel,
            tssType: tssType,
            backupType: backupType,
            isNewVault: isNewVault
        ) {
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
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                passwordFieldFocused = true
            }

            backupViewModel.resetData()
        }
        .onDisappear {
            backupViewModel.resetData()
        }
        .onChange(of: verifyPassword) { _, _ in
            if backupViewModel.encryptionPassword == verifyPassword {
                passwordErrorMessage = ""
                passwordVerifyErrorMessage = ""
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

        Task {
            guard let fileModel = await backupViewModel.exportFileWithCustomPassword(backupType) else {
                return
            }

            await MainActor.run {
                self.fileModel = fileModel
                presentFileExporter = true
            }
        }
    }
}

#Preview {
    VaultBackupPasswordScreen(tssType: .Keygen, backupType: .single(vault: Vault.example))
}
