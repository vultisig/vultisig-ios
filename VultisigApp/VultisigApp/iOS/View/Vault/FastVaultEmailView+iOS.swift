//
//  FastVaultEmailView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(iOS)
import SwiftUI

extension FastVaultEmailView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationBarBackButtonHidden(backButtonHidden)
        .navigationTitle(NSLocalizedString("", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }

    var main: some View {
        view
    }

    var view: some View {
        VStack {
            emailField

            if isEmptyEmail {
                emptyEmailLabel
            } else if isInvalidEmail {
                validEmailLabel
            }

            Spacer()
            button
        }
    }

    func textfield(title: String, text: Binding<String>) -> some View {
        HStack {
            TextField("", text: text, prompt: Text(NSLocalizedString(title, comment: ""))
                .foregroundColor(Theme.colors.textTertiary)
                .font(Theme.fonts.bodyMMedium)
            )
            .font(Theme.fonts.bodyMRegular)
            .foregroundColor(Theme.colors.textPrimary)
            .submitLabel(.done)
            .focused($isEmailFocused)
            .onSubmit {
                handleTap()
            }
            if !email.isEmpty {
                clearButton
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 12)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(getBorderColor(), lineWidth: 1)
        )
        .textInputAutocapitalization(.never)
        .keyboardType(.emailAddress)
        .autocorrectionDisabled()
        .borderlessTextFieldStyle()
        .padding(.top, 32)
    }
}
#endif
