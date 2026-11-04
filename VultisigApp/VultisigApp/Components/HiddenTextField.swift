//
//  HiddenTextField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-16.
//

import SwiftUI

struct HiddenTextField: View {
    let placeholder: String
    @Binding var password: String
    var showHideOption: Bool = true
    var errorMessage: String
    var isFocused: Bool = false

    @State var isPasswordVisible: Bool = false

    var body: some View {
        VStack {
            field

            if !errorMessage.isEmpty {
                error
            }
        }
        .animation(.easeInOut, value: errorMessage)
        .onAppear {
            setData()
        }
    }

    var error: some View {
        Text(NSLocalizedString(errorMessage, comment: ""))
            .font(Theme.fonts.bodySMedium)
            .foregroundStyle(Theme.colors.alertError)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var field: some View {
        HStack {
            textfield

            if showHideOption {
                button
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 16)
        .background(Theme.colors.bgSurface1)
        .clipShape(Theme.radius.lg.shape)
        .overlay(Theme.radius.lg.shape.strokeBorder(borderColor, lineWidth: 1))
    }

    private var borderColor: Color {
        if !errorMessage.isEmpty {
            return Theme.colors.alertError
        }
        return isFocused ? Theme.colors.borderNormal : Theme.colors.borderExtraLight
    }

    var textfield: some View {
        ZStack(alignment: .leading) {
            if password.isEmpty {
                HStack {
                    Text(NSLocalizedString(placeholder, comment: ""))
                        .foregroundStyle(Theme.colors.textTertiary)
                    Spacer()
                }
            }

            if isPasswordVisible {
                 TextField(NSLocalizedString("", comment: ""), text: $password)
                    .borderlessTextFieldStyle()
            } else {
                SecureField(NSLocalizedString("", comment: ""), text: $password)
                    .borderlessTextFieldStyle()
            }
        }
        .submitLabel(.done)
        .colorScheme(.dark)
        .font(Theme.fonts.bodySMedium)
        .foregroundStyle(Theme.colors.textPrimary)
    }

    var button: some View {
        Button(
            action: {
                withAnimation {
                    isPasswordVisible.toggle()
                }
            },
            label: {
                Icon(isPasswordVisible ? .eye : .eyeClosed, color: Theme.colors.textPrimary, size: 20)
            }
        )
        .buttonStyle(.plain)
        .contentTransition(.symbolEffect(.replace))
    }

    private func setData() {
        if !showHideOption {
            isPasswordVisible = true
        }
    }
}

#Preview {
    ZStack {
        Background()
        VStack {
            HiddenTextField(placeholder: "verifyPassword", password: .constant("password"), errorMessage: "")
            HiddenTextField(placeholder: "verifyPassword", password: .constant(""), errorMessage: "")
        }
    }
}
