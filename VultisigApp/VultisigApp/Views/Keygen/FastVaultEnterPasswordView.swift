//
//  FastVaultEnterPasswordView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 12.09.2024.
//

import SwiftUI

struct FastVaultEnterPasswordView: View {

    @AppStorage("isBiometryEnabled") var isBiometryEnabled: Bool = false

    @State var isLoading: Bool = false
    @State var isWrongPassword: Bool = false

    @Binding var password: String

    @Environment(\.dismiss) var dismiss

    let vault: Vault
    let onSubmit: (() -> Void)?

    private let keychain = DefaultKeychainService.shared
    private let biometryService = BiometryService.shared

    var view: some View {
        VStack {
            passwordField
            Spacer(minLength: 20)
            disclaimer
            buttons
        }
        .onAppear {
            tryAuthenticate()
        }
    }

    var passwordField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FastVault password")
                .font(.body14MontserratMedium)
                .foregroundColor(.neutral0)

            textfield
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
    }

    var textfield: some View {
        HiddenTextField(placeholder: "enterPassword", password: $password)
            .padding(.top, 8)
    }

    var disclaimer: some View {
        OutlinedDisclaimer(text: NSLocalizedString("fastVaultEnterDisclaimer", comment: ""))
            .padding(.horizontal, 16)
    }

    var buttons: some View {
        VStack(spacing: 20) {
            continueButton
        }
        .padding(.top, 16)
        .padding(.bottom, 40)
        .padding(.horizontal, 16)
    }

    var continueButton: some View {
        Button(action: {
            Task {
                await checkPassword()
            }
        }) {
            FilledButton(title: "continue")
        }
        .opacity(isSaveButtonDisabled ? 0.5 : 1)
        .disabled(isSaveButtonDisabled)
        .buttonStyle(.plain)
        .alert(NSLocalizedString("wrongPassword", comment: ""), isPresented: $isWrongPassword) {
            Button("OK", role: .cancel) { }
        }
    }

    var isSaveButtonDisabled: Bool {
        return password.isEmpty
    }

    @MainActor func checkPassword() async {
        isLoading = true
        defer { isLoading = false }

        let isValidPassword = await FastVaultService.shared.get(
            pubKeyECDSA: vault.pubKeyECDSA,
            password: password
        )

        if isValidPassword {
            savePassword()
            onSubmit?()
            dismiss()
        } else {
            isWrongPassword = true
        }
    }

    func savePassword() {
        keychain.setFastPassword(password, pubKeyECDSA: vault.pubKeyECDSA)
    }

    func tryAuthenticate() {
        guard let fastPassword = keychain.getFastPassword(pubKeyECDSA: vault.pubKeyECDSA) else {
            return
        }

        guard !fastPassword.isEmpty, isBiometryEnabled else {
            return
        }

        biometryService.authenticate(
            reason: "Authenticate to fill FastServer password",
            onSuccess: {
                password = fastPassword
                onSubmit?()
                dismiss()
            },
            onError: nil)
    }
}

