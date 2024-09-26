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

    @State var password: String = ""
    @State var verifyPassword: String = ""
    @State var isLinkActive = false

    var title: String {
        switch tssType {
        case .Keygen:
            return "Protect your FastVault."
        case .Reshare:
            return "FastVault password"
        }
    }

    var disclaimerText: String {
        switch tssType {
        case .Keygen:
            return NSLocalizedString("fastVaultSetDisclaimer", comment: "")
        case .Reshare:
            return NSLocalizedString("fastVaultEnterDisclaimer", comment: "")
        }
    }

    var body: some View {
        content
    }

    var passwordField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.body14MontserratMedium)
                .foregroundColor(.neutral0)

            textfield
            verifyTextfield
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
    }

    var textfield: some View {
        HiddenTextField(placeholder: "enterPassword", password: $password)
            .padding(.top, 8)
    }

    var verifyTextfield: some View {
        HiddenTextField(placeholder: "verifyPassword", password: $verifyPassword)
            .opacity(tssType == .Keygen ? 1 : 0)
    }

    var disclaimer: some View {
        OutlinedDisclaimer(text: disclaimerText)
            .padding(.horizontal, 16)
    }

    var buttons: some View {
        VStack(spacing: 20) {
            saveButton
        }
        .padding(.top, 16)
        .padding(.bottom, 40)
        .padding(.horizontal, 16)
    }

    var saveButton: some View {
        Button(action: {
            isLinkActive = true
        }) {
            FilledButton(title: "continue")
        }
        .opacity(isSaveButtonDisabled ? 0.5 : 1)
        .disabled(isSaveButtonDisabled)
    }

    var isSaveButtonDisabled: Bool {
        switch tssType {
        case .Keygen:
            return password.isEmpty || password != verifyPassword
        case .Reshare:
            return password.isEmpty
        }
    }
}
