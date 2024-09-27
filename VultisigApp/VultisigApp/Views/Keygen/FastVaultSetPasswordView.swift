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

    var title: String {
        switch fastVaultExist {
        case false:
            return NSLocalizedString("fastVaultSetPasswordTitle", comment: "")
        case true:
            return NSLocalizedString("fastVaultEnterPasswordTitle", comment: "")
        }
    }

    var disclaimerText: String {
        switch fastVaultExist {
        case false:
            return NSLocalizedString("fastVaultSetDisclaimer", comment: "")
        case true:
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
            .opacity(fastVaultExist ? 0 : 1)
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
        switch fastVaultExist {
        case false:
            return password.isEmpty || password != verifyPassword
        case true:
            return password.isEmpty
        }
    }
}
