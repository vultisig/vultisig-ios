//
//  HiddenTextField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-16.
//

import SwiftUI

/// `.settings`: the settings forms' 52 tall field, with a border that follows focus.
enum HiddenTextFieldAppearance {
    case standard, settings
}

struct HiddenTextField: View {
    let placeholder: String
    @Binding var password: String
    var showHideOption: Bool = true
    var errorMessage: String
    var appearance: HiddenTextFieldAppearance = .standard
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
        .frame(height: isSettings ? 52 : 56)
        .padding(.horizontal, 16)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(isSettings ? Theme.radius.lg : Theme.radius.md)
        .overlay(fieldBorder)
    }

    private var isSettings: Bool {
        appearance == .settings
    }

    @ViewBuilder
    private var fieldBorder: some View {
        if isSettings {
            Theme.radius.lg.shape.strokeBorder(settingsBorderColor, lineWidth: 1)
        } else {
            Theme.radius.md.shape
                .stroke(errorMessage.isEmpty ? Theme.colors.border : Theme.colors.alertError, lineWidth: 1)
        }
    }

    private var settingsBorderColor: Color {
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
        .font(isSettings ? Theme.fonts.bodySMedium : Theme.fonts.bodyMMedium)
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
                if isSettings {
                    Icon(isPasswordVisible ? .eye : .eyeClosed, color: Theme.colors.textPrimary, size: 20)
                        .accessibilityRepresentation {
                            Image(systemName: isPasswordVisible ? "eye": "eye.slash")
                        }
                } else {
                    Image(systemName: isPasswordVisible ? "eye": "eye.slash")
                        .foregroundStyle(Theme.colors.textPrimary)
                }
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
