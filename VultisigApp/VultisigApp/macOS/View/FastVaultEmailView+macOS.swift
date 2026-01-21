//
//  FastVaultEmailView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(macOS)
import SwiftUI

extension FastVaultEmailView {
    var content: some View {
        ZStack {
            Background()
            view
        }
        .crossPlatformToolbar(showsBackButton: !backButtonHidden)
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
        .padding(.horizontal, 25)
    }

    func textfield(title: String, text: Binding<String>) -> some View {
        HStack {
            TextField("", text: text, prompt: Text(NSLocalizedString(title, comment: ""))
                .foregroundColor(Theme.colors.textTertiary)
                .font(Theme.fonts.caption12)
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
        .padding(12)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(12)
        .autocorrectionDisabled()
        .borderlessTextFieldStyle()
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(getBorderColor(), lineWidth: 1)
        )
        .padding(.top, 32)
    }
}
#endif
