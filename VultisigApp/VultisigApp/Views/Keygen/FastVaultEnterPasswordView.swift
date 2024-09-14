//
//  FastVaultEnterPasswordView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 12.09.2024.
//

import SwiftUI

struct FastVaultEnterPasswordView: View {

    @Binding var password: String

    @Environment(\.dismiss) var dismiss

    let onSubmit: (() -> Void)?

    var view: some View {
        VStack {
            passwordField
            Spacer(minLength: 20)
            disclaimer
            buttons
        }
    }

    var passwordField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FastVault password")
                .font(.body14MontserratMedium)
                .foregroundColor(.neutral0)

            textfield
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
    }

    var textfield: some View {
        HiddenTextField(placeholder: "enterPassword", password: $password)
            .padding(.top, 8)
    }

    var disclaimer: some View {
        OutlinedDisclaimer(text: "This Password decrypt your FastVault Share")
            .padding(.horizontal, 16)
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
            onSubmit?()
            dismiss()
        }) {
            FilledButton(title: "Continue")
        }
        .opacity(isSaveButtonDisabled ? 0.5 : 1)
        .disabled(isSaveButtonDisabled)
        .buttonStyle(.plain)
    }

    var isSaveButtonDisabled: Bool {
        return password.isEmpty
    }
}

