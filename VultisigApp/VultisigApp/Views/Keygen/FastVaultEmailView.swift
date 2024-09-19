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
        content
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
