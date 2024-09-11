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

    var body: some View {
        ZStack {
            Background()
            main
        }
#if os(iOS)
            .navigationTitle("Password")
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
            PeerDiscoveryView(tssType: tssType, vault: vault, selectedTab: selectedTab, fastVaultEmail: fastVaultEmail, fastVaultPassword: password)
        }
    }

    var headerMac: some View {
        GeneralMacHeader(title: "Password")
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
            Text("Protect your FastVault.")
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
            isLinkActive = true
        }) {
            FilledButton(title: "Continue")
        }
        .opacity(isSaveButtonDisabled ? 0.5 : 1)
        .disabled(isSaveButtonDisabled)
    }

    var isSaveButtonDisabled: Bool {
        return password != verifyPassword
    }
}
