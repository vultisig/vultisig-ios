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
    @State var isLoading: Bool = false
    @State var isWrongPassword: Bool = false
    @State var showTooltip = false
    
    @State var passwordFieldError = ""
    @State var verifyFieldError = ""
    @FocusState var isPasswordFieldFocused: Bool
    @FocusState var isVerifyPasswordFieldFocused: Bool
    @Environment(\.router) var router
    private let fastVaultService: FastVaultService = .shared

    var body: some View {
        content
            .animation(.easeInOut, value: showTooltip)
            .alert(NSLocalizedString("wrongPassword", comment: ""), isPresented: $isWrongPassword) {
                Button("OK", role: .cancel) { }
            }
            .onLoad {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isPasswordFieldFocused = true
                }
            }
            .onChange(of: password) { oldValue, newValue in
                _ = validatePassword()
            }
            .onChange(of: verifyPassword) { oldValue, newValue in
                _ = validatePassword()
            }
    }

    private func handleNavigation() {
        if tssType == .Migrate {
            router.navigate(to: KeygenRoute.peerDiscovery(
                tssType: tssType,
                vault: vault,
                selectedTab: selectedTab,
                fastSignConfig: fastSignConfig,
                keyImportInput: nil
            ))
        } else {
            router.navigate(to: KeygenRoute.fastVaultSetHint(
                tssType: tssType,
                vault: vault,
                selectedTab: selectedTab,
                fastVaultEmail: fastVaultEmail,
                fastVaultPassword: password,
                fastVaultExist: fastVaultExist
            ))
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
                    .zIndex(1)
                Group {
                    textfield
                    verifyTextfield
                }.zIndex(0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
    }
    
    var title: some View {
        Text(NSLocalizedString("vultiserverPassword", comment: ""))
            .font(Theme.fonts.largeTitle)
            .foregroundColor(Theme.colors.textPrimary)
    }
    
    var migrateDescription: some View {
        Text(NSLocalizedString("migratePasswordDescription", comment: ""))
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textTertiary)
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
        PrimaryButton(title: "next") {
            handleSubmit()
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
        handleNavigation()
    }
    func validatePassword()->Bool {
        guard !password.isEmpty else {
            verifyFieldError = ""
            passwordFieldError = "emptyField"
            return false
        }
        
        guard !verifyPassword.isEmpty else {
            verifyFieldError = "emptyField"
            passwordFieldError = ""
            return false
        }
        
        guard password == verifyPassword else {
            verifyFieldError = "passwordMismatch"
            passwordFieldError = "passwordMismatch"
            return false
        }
        verifyFieldError = ""
        passwordFieldError = ""
        return true
    }
    private func handleTap() {
        if validatePassword() {
            handleNavigation()
        }
    }
}

