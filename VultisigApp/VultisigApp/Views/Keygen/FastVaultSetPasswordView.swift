//
//  FastVaultPasswordView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 10.09.2024.
//

import SwiftUI

struct FastVaultSetPasswordView: View {
    let tssType: TssType
    let vault: Vault
    let selectedTab: SetupVaultState
    let fastVaultEmail: String
    let fastVaultExist: Bool

    @State var password: String = ""
    @State var verifyPassword: String = ""
    @State var isLinkActive = false
    @State var isLoading: Bool = false
    @State var isWrongPassword: Bool = false
    @State var showTooltip = false
    
    @State var passwordFieldError = ""
    @State var verifyFieldError = ""

    private let fastVaultService: FastVaultService = .shared

    var body: some View {
        content
            .animation(.easeInOut, value: showTooltip)
            .alert(NSLocalizedString("wrongPassword", comment: ""), isPresented: $isWrongPassword) {
                Button("OK", role: .cancel) { }
            }
    }

    var passwordField: some View {
        VStack(alignment: .leading, spacing: 12) {
            title
            disclaimer
            textfield
            verifyTextfield
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
        .onAppear {
            isLinkActive = false
        }
    }
    
    var title: some View {
        Text(NSLocalizedString("password", comment: ""))
            .font(.body34BrockmannMedium)
            .foregroundColor(.neutral0)
    }
    
    var disclaimer: some View {
        FastVaultPasswordDisclaimer(showTooltip: $showTooltip)
    }

    var textfield: some View {
        HiddenTextField(
            placeholder: "enterPassword",
            password: $password,
            errorMessage: passwordFieldError
        )
        .padding(.top, 32)
    }

    var verifyTextfield: some View {
        HiddenTextField(
            placeholder: "verifyPassword",
            password: $verifyPassword,
            errorMessage: verifyFieldError
        )
        .opacity(fastVaultExist ? 0 : 1)
    }

    var button: some View {
        Button(action: {
            if fastVaultExist {
                Task { await checkPassword() }
            } else {
                handleTap()
            }
        }) {
            FilledButton(title: "next")
        }
        .padding(.top, 16)
        .padding(.bottom, 40)
        .padding(.horizontal, 16)
    }

    @MainActor func checkPassword() async {
        isLoading = true
        defer { isLoading = false }

        let isValid = await fastVaultService.get(
            pubKeyECDSA: vault.pubKeyECDSA,
            password: password
        )

        guard isValid else {
            isWrongPassword = true
            password = .empty
            return
        }

        isLinkActive = true
    }
    
    private func handleTap() {
        guard !password.isEmpty else {
            verifyFieldError = ""
            passwordFieldError = "emptyField"
            return
        }
        
        guard !verifyPassword.isEmpty else {
            verifyFieldError = "emptyField"
            passwordFieldError = ""
            return
        }
        
        guard password == verifyPassword else {
            verifyFieldError = "passwordMismatch"
            passwordFieldError = "passwordMismatch"
            return
        }
        
        isLinkActive = true
    }
}
