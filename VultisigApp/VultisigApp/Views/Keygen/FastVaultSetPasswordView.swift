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
    @FocusState var isPasswordFieldFocused: Bool
    @FocusState var isVerifyPasswordFieldFocused: Bool
    private let fastVaultService: FastVaultService = .shared

    var body: some View {
        content
            .animation(.easeInOut, value: showTooltip)
            .alert(NSLocalizedString("wrongPassword", comment: ""), isPresented: $isWrongPassword) {
                Button("OK", role: .cancel) { }
            }
            .navigationDestination(isPresented: $isLinkActive) {
                if tssType == .Migrate {
                    PeerDiscoveryView(tssType: tssType, vault: vault, selectedTab: selectedTab, fastSignConfig: fastSignConfig)
                } else {
                    FastVaultSetHintView(tssType: tssType, vault: vault, selectedTab: selectedTab, fastVaultEmail: fastVaultEmail, fastVaultPassword: password, fastVaultExist: fastVaultExist)
                }
            }
            .onAppear() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isPasswordFieldFocused = true
                }
            }
    }

    var passwordField: some View {
        VStack(alignment: .leading, spacing: 12) {
            title
            
            if tssType == .Migrate {
                migrateDescription
                textfield
            } else {
                disclaimer
                textfield
                verifyTextfield
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
        .onAppear {
            isLinkActive = false
        }
    }
    
    var title: some View {
        Text(NSLocalizedString("vultiserverPassword", comment: ""))
            .font(.body34BrockmannMedium)
            .foregroundColor(.neutral0)
    }
    
    var migrateDescription: some View {
        Text(NSLocalizedString("migratePasswordDescription", comment: ""))
            .font(.body14BrockmannMedium)
            .foregroundColor(.extraLightGray)
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
        .submitLabel(.next)
        .focused($isPasswordFieldFocused)
        .onSubmit {
            isVerifyPasswordFieldFocused = true
        }
        .padding(.top, 32)
    }

    var verifyTextfield: some View {
        HiddenTextField(
            placeholder: "verifyPassword",
            password: $verifyPassword,
            errorMessage: verifyFieldError
        )
        .focused($isVerifyPasswordFieldFocused)
        .onSubmit {
            handleSubmit()
        }
        .opacity(fastVaultExist ? 0 : 1)
    }
    func handleSubmit(){
        if fastVaultExist {
            Task { await checkPassword() }
        } else {
            handleTap()
        }
    }
    var button: some View {
        Button(action: {
            handleSubmit()
        }) {
            FilledButton(title: "next")
        }
        .padding(.top, 16)
        .padding(.bottom, 40)
        .padding(.horizontal, 16)
    }
    
    var fastSignConfig: FastSignConfig {
        return FastSignConfig(
            email: fastVaultEmail,
            password: password,
            hint: .empty,
            isExist: fastVaultExist
        )
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
