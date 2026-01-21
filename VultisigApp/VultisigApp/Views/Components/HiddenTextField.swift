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
            .foregroundColor(Theme.colors.alertError)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var field: some View {
        HStack {
            textfield

            if showHideOption {
                button
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 16)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(errorMessage.isEmpty ? Theme.colors.border : Theme.colors.alertError, lineWidth: 1)
        )
    }

    var textfield: some View {
        ZStack(alignment: .leading) {
            if password.isEmpty {
                HStack {
                    Text(NSLocalizedString(placeholder, comment: ""))
                        .foregroundColor(Theme.colors.textTertiary)
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
        .font(Theme.fonts.bodyMMedium)
        .foregroundColor(Theme.colors.textPrimary)
    }

    var button: some View {
        Button(
            action: {
                withAnimation {
                    isPasswordVisible.toggle()
                }
            },
            label: {
                Image(systemName: isPasswordVisible ? "eye": "eye.slash")
                    .foregroundColor(Theme.colors.textPrimary)
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
