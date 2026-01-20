//
//  FastVaultEmailView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 11.09.2024.
//

import SwiftUI

struct FastVaultEmailView: View {
    let tssType: TssType
    let vault: Vault
    let selectedTab: SetupVaultState

    var fastVaultExist: Bool = false
    var backButtonHidden: Bool = false

    @State var email: String = ""
    
    @State var isEmptyEmail: Bool = false
    @State var isInvalidEmail: Bool = false
    @FocusState var isEmailFocused: Bool
    @Environment(\.router) var router

    var body: some View {
        content
            .onChange(of: email) { _ ,newValue in
                if !newValue.isEmpty {
                    isEmptyEmail = false
                }
                
                if isInvalidEmail && newValue.isValidEmail {
                    isInvalidEmail = false
                }
            }
            .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isEmailFocused = true
            }
        }
    }

    var emailField: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("enterYourEmail", comment: ""))
                .font(Theme.fonts.largeTitle)
                .foregroundColor(Theme.colors.textPrimary)
                .padding(.top, 16)
            
            Text(NSLocalizedString("enterYourEmailDescription", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textTertiary)
            
            textfield(title: NSLocalizedString("email", comment: ""),text: $email)
        }
        .padding(.horizontal, 16)
        .animation(.easeInOut, value: isEmptyEmail)
        .animation(.easeInOut, value: isInvalidEmail)
        
    }

    var emptyEmailLabel: some View {
        HStack {
            Text(NSLocalizedString("emptyEmailPleaseCheck", comment: ""))
                .foregroundColor(Theme.colors.alertError)
                .font(Theme.fonts.bodySRegular)
                .frame(height: 40)
            Spacer()
        }
        .padding(.horizontal, 16)
    }
    
    var validEmailLabel: some View {
        HStack {
            Text(NSLocalizedString("invalidEmailPleaseCheck", comment: ""))
                .foregroundColor(Theme.colors.alertError)
                .font(Theme.fonts.bodySRegular)
                .frame(height: 40)
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    var button: some View {
        continueButton
            .padding(.top, 16)
            .padding(.bottom, 40)
            .padding(.horizontal, 16)
    }

    var continueButton: some View {
        PrimaryButton(title: "next") {
            handleTap()
        }
    }
    
    var clearButton: some View {
        Button {
            isEmailFocused = false
            email = ""
            isEmptyEmail = true
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(Theme.colors.textTertiary)
        }
    }
    
    func handleTap() {
        guard isEmptyEmailCheck() else {
            isEmptyEmail = true
            return
        }
        
        isEmptyEmail = false
        guard isValidEmailCheck() else {
            isInvalidEmail = true
            return
        }
        
        isInvalidEmail = false
        
        router.navigate(to: KeygenRoute.fastVaultSetPassword(
            tssType: tssType,
            vault: vault,
            selectedTab: selectedTab,
            fastVaultEmail: email,
            fastVaultExist: fastVaultExist
        ))
    }
    
    private func isEmptyEmailCheck() -> Bool {
        return !email.isEmpty
    }

    private func isValidEmailCheck() -> Bool {
        return !email.trimmingCharacters(in: .whitespaces).isEmpty &&
               !email.isEmpty &&
                email.isValidEmail
    }
    
    func getBorderColor() -> Color {
        if isEmptyEmail || isInvalidEmail {
            return Theme.colors.alertError
        } else {
            return Theme.colors.border
        }
    }
}
