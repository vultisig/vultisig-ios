//
//  CommonTextEditor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/09/2025.
//

import SwiftUI

struct CommonTextEditor: View {
    @Environment(\.isEnabled) var isEnabled
    @Binding var value: String
    let placeholder: String
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void
    @Binding var error: String?
    @Binding var isValid: Bool?
    let showErrorText: Bool
    let accessory: String?

    init(
        value: Binding<String>,
        placeholder: String,
        isFocused: FocusState<Bool>.Binding,
        onSubmit: @escaping () -> Void = {},
        error: Binding<String?> = .constant(nil),
        isValid: Binding<Bool?> = .constant(nil),
        showErrorText: Bool = true,
        accessory: String? = nil
    ) {
        self._value = value
        self.placeholder = placeholder
        self.isFocused = isFocused
        self.onSubmit = onSubmit
        self._error = error
        self._isValid = isValid
        self.showErrorText = showErrorText
        self.accessory = accessory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                HStack {
                    TextEditor(text: $value)
                        .textEditorStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .foregroundColor(Theme.colors.textPrimary)
                        .font(Theme.fonts.bodyMMedium)
                        .submitLabel(.continue)
                        .autocorrectionDisabled()
                        .focused(isFocused)
                        .onSubmit {
                            onSubmit()
                        }

                    if !value.isEmpty {
                        VStack {
                            clearButton
                                .showIf(isEnabled)
                            Spacer()
                        }
                    }
                }
                if value.isEmpty {
                    Text(placeholder)
                        .foregroundColor(Theme.colors.textTertiary)
                        .font(Theme.fonts.bodyMMedium)
                        .padding(.leading, 6)
                        .padding(.top, isMacOS ? 0 : 8)
                }

                if let accessory {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(accessory)
                                .foregroundColor(Theme.colors.textTertiary)
                                .font(Theme.fonts.caption12)
                        }
                    }
                }
            }
            .frame(height: 120)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 1)
            )
            .padding(1)

            if let error, showErrorText {
                Text(error.localized)
                    .foregroundColor(Theme.colors.alertError)
                    .font(Theme.fonts.footnote)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.easeInOut, value: error)
        .animation(.easeInOut, value: isValid)
    }

    var borderColor: Color {
        if let isValid, isValid {
            return Theme.colors.alertSuccess
        }

        return (error != nil && error != .empty) ? Theme.colors.alertError : Theme.colors.border
    }

    var clearButton: some View {
        Button {
            value = ""
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(Theme.colors.textTertiary)
        }
    }
}
