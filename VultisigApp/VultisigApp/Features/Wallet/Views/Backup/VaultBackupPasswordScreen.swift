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
    var origin: VaultBackupOrigin = .standard

    @State var verifyPassword: String = ""

    @StateObject var backupViewModel = EncryptedBackupViewModel()
    @State var presentFileExporter = false
    @State var fileModel: FileExporterModel<EncryptedDataFile>?
    @State var activityItems: [Any] = []
    @State var passwordErrorMessage: String = ""
    @State var passwordVerifyErrorMessage: String = ""
    @FocusState var passwordFieldFocused
    @FocusState var passwordVerifyFieldFocused
    private let verifyFieldId = "verifyField"

    var body: some View {
        VaultBackupContainerView(
            presentFileExporter: $presentFileExporter,
            fileModel: $fileModel,
            backupViewModel: backupViewModel,
            tssType: tssType,
            backupType: backupType,
            isNewVault: isNewVault,
            origin: origin
        ) {
            screen
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
    var screen: some View {
        if origin.usesSettingsLook {
            Screen {
                VStack(spacing: 12) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            settingsPasswordField
                        }
                        .scrollIndicatorsFlash(onAppear: true)
                        .onChange(of: passwordVerifyFieldFocused) { _, _ in
                            scrollToVerifyField(proxy)
                        }
                        .onChange(of: passwordVerifyErrorMessage) { _, _ in
                            scrollToVerifyField(proxy)
                        }
                    }
                    settingsSaveButton
                }
            }
            .screenEdgeInsets(ScreenEdgeInsets(top: 3))
        } else {
            Screen {
                VStack {
                    passwordField
                    Spacer()
                    VStack(spacing: 16) {
                        disclaimer
                        saveButton
                    }
                }
            }
            .screenTitle("backup".localized)
        }
    }

    private func scrollToVerifyField(_ proxy: ScrollViewProxy) {
        guard passwordVerifyFieldFocused || !passwordVerifyErrorMessage.isEmpty else { return }
        withAnimation {
            proxy.scrollTo(verifyFieldId, anchor: .bottom)
        }
    }

    @ViewBuilder
    var saveButton: some View {
        PrimaryButton(title: "save") {
            onSave()
        }
    }

    var settingsSaveButton: some View {
        PrimaryButton(title: "deviceBackupPasswordButton", size: .compactSemibold) {
            onSave()
        }
    }

    var passwordField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("optionalPasswordProtectBackup", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            textfield
            verifyTextfield
        }
    }

    var settingsPasswordField: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("deviceBackupPasswordTitle".localized)
                .settingsText(.largeTitle)
                .foregroundStyle(Theme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            InfoBannerView(
                description: "PasswordCannotBeReset".localized + "\n" + "backupPasswordDisclaimer".localized,
                type: .warning,
                leadingIcon: nil,
                trailingIcon: .circleInfo,
                appearance: .settings
            )

            VStack(spacing: 8) {
                settingsTextfield
                settingsVerifyTextfield
                    .id(verifyFieldId)
            }
            .padding(.top, 13)
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

    var settingsTextfield: some View {
        HiddenTextField(placeholder: "settingsEnterPassword",
                        password: $backupViewModel.encryptionPassword,
                        errorMessage: passwordErrorMessage,
                        appearance: .settings,
                        isFocused: passwordFieldFocused)
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

    var settingsVerifyTextfield: some View {
        HiddenTextField(
            placeholder: "settingsReEnterPassword",
            password: $verifyPassword,
            errorMessage: passwordVerifyErrorMessage,
            appearance: .settings,
            isFocused: passwordVerifyFieldFocused
        )
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
