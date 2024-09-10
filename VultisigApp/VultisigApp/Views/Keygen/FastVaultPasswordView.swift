//
//  FastVaultPasswordView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 10.09.2024.
//

import SwiftUI

struct FastVaultPasswordView: View {
    @Binding var password: String
    @State var verifyPassword: String = ""

    let onSubmit: (() -> Void)?

    var body: some View {
        ZStack {
            Background()
            main
        }
#if os(iOS)
            .navigationTitle(NSLocalizedString("password", comment: "Password"))
#endif
    }

    var main: some View {
        VStack {
#if os(macOS)
            headerMac
#endif
            view
        }
    }

    var headerMac: some View {
        GeneralMacHeader(title: "password")
    }

    var view: some View {
        VStack {
            passwordField
            Spacer()
            disclaimer
            buttons
        }
#if os(macOS)
        .padding(.horizontal, 25)
#endif
    }

    var passwordField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Protect your vault.", comment: ""))
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
    }

    var disclaimer: some View {
        OutlinedDisclaimer(text: "This Password encrypts your FastVault Share")
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
            onSubmit?()
        }) {
            FilledButton(title: "save")
        }
        .disabled(password != verifyPassword)
    }
}
