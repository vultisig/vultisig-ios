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
    @State var isLinkActive = false
    
    @State var isEmptyEmail: Bool = false
    @State var isInvalidEmail: Bool = false
    @FocusState var isEmailFocused: Bool
    
    var body: some View {
        content
            .onChange(of: email) { _ ,newValue in
                if !newValue.isEmpty {
                    isEmptyEmail = false
                }
            }
            .onAppear(){
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isEmailFocused = true
            }
        }
    }

    var emailField: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("enterYourEmail", comment: ""))
                .font(Theme.fonts.largeTitle)
                .foregroundColor(.neutral0)
                .padding(.top, 16)
            
            Text(NSLocalizedString("enterYourEmailDescription", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(.extraLightGray)
            
            textfield(title: NSLocalizedString("email", comment: ""),text: $email)
        }
        .padding(.horizontal, 16)
        .animation(.easeInOut, value: isEmptyEmail)
        .animation(.easeInOut, value: isInvalidEmail)
        
    }

    var emptyEmailLabel: some View {
        HStack {
            Text(NSLocalizedString("emptyEmailPleaseCheck", comment: ""))
                .foregroundColor(.alertRed)
                .font(Theme.fonts.bodySRegular)
                .frame(height: 40)
            Spacer()
        }
        .padding(.horizontal, 16)
    }
    
    var validEmailLabel: some View {
        HStack {
            Text(NSLocalizedString("invalidEmailPleaseCheck", comment: ""))
                .foregroundColor(.alertRed)
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
                .foregroundColor(.neutral500)
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
        isLinkActive = true
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
            return .alertRed
        } else {
            return .blue200
        }
    }
}
