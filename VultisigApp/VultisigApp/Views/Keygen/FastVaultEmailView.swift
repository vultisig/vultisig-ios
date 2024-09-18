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

    @State var email: String = ""
    @State var verifyEmail: String = ""
    @State var isLinkActive = false

    var body: some View {
        ZStack {
            Background()
            main
        }
#if os(iOS)
            .navigationTitle(NSLocalizedString("email", comment: ""))
#endif
    }

    var main: some View {
        VStack {
#if os(macOS)
            headerMac
#endif
            view
        }
        .navigationDestination(isPresented: $isLinkActive) {
            FastVaultSetPasswordView(tssType: tssType, vault: vault, selectedTab: selectedTab, fastVaultEmail: email)
        }
    }

    var headerMac: some View {
        GeneralMacHeader(title: "email")
    }

    var view: some View {
        VStack {
            emailField
            Spacer()
            buttons
        }
#if os(macOS)
        .padding(.horizontal, 25)
#endif
    }

    var emailField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("fastVaultEmailBackup", comment: ""))
                .font(.body14MontserratMedium)
                .foregroundColor(.neutral0)

            textfield(title: NSLocalizedString("email", comment: ""), text: $email)
            textfield(title: NSLocalizedString("verifyEmail", comment: ""), text: $verifyEmail)
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
    }

    func textfield(title: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(NSLocalizedString(title, comment: ""))
            .foregroundColor(Color.neutral500)
            .font(.body12Menlo)
        )
        .font(.body16Menlo)
        .foregroundColor(.neutral0)
        .submitLabel(.done)
        .padding(12)
        .background(Color.blue600)
        .cornerRadius(12)
#if os(iOS)
        .textInputAutocapitalization(.never)
        .keyboardType(.emailAddress)
#endif
        .autocorrectionDisabled()
        .borderlessTextFieldStyle()
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
            isLinkActive = true
        }) {
            FilledButton(title: "continue")
        }
        .opacity(isValid ? 1 : 0.5)
        .disabled(!isValid)
    }

    var isValid: Bool {
        return !email.trimmingCharacters(in: .whitespaces).isEmpty && 
               !email.isEmpty &&
                email.isValidEmail &&
                email == verifyEmail
    }
}
