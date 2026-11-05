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
    let appearance: CommonTextFieldAppearance

    /// Cancels `UITextView`'s own insets so the text sits on the design's 16pt padding.
    private static var settingsTextViewOutset: EdgeInsets {
        EdgeInsets(top: isMacOS ? 0 : -8, leading: -5, bottom: isMacOS ? 0 : -8, trailing: -5)
    }

    private static var settingsLineSpacing: CGFloat { 3 }
    private static var settingsHeight: CGFloat { 120 }
    private static var settingsPadding: CGFloat { 16 }

    init(
        value: Binding<String>,
        placeholder: String,
        isFocused: FocusState<Bool>.Binding,
        onSubmit: @escaping () -> Void = {},
        error: Binding<String?> = .constant(nil),
        isValid: Binding<Bool?> = .constant(nil),
        showErrorText: Bool = true,
        accessory: String? = nil,
        appearance: CommonTextFieldAppearance = .standard
    ) {
        self._value = value
        self.placeholder = placeholder
        self.isFocused = isFocused
        self.onSubmit = onSubmit
        self._error = error
        self._isValid = isValid
        self.showErrorText = showErrorText
        self.accessory = accessory
        self.appearance = appearance
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            editorBox

            if let error, showErrorText {
                Text(error.localized)
                    .foregroundStyle(Theme.colors.alertError)
                    .font(Theme.fonts.footnote)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.easeInOut, value: error)
        .animation(.easeInOut, value: isValid)
    }

    @ViewBuilder
    private var editorBox: some View {
        if appearance != .standard {
            editorContent
                .padding(Self.settingsPadding)
                .frame(height: Self.settingsHeight)
                .background(
                    Theme.radius.lg.shape
                        .fill(Theme.colors.bgSurface1)
                        .strokeBorder(settingsBorderColor, lineWidth: 1)
                )
        } else {
            editorContent
                .frame(height: 120)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.colors.bgSurface1)
                .cornerRadius(Theme.radius.md)
                .overlay(
                    Theme.radius.md.shape
                        .stroke(borderColor, lineWidth: 1)
                )
                .padding(1)
        }
    }

    private var editorContent: some View {
        ZStack(alignment: .topLeading) {
            HStack {
                TextEditor(text: $value)
                    .textEditorStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(appearance != .standard ? Theme.fonts.bodySMedium : Theme.fonts.bodyMMedium)
                    .lineSpacing(appearance != .standard ? Self.settingsLineSpacing : 0)
                    .padding(appearance == .standard ? EdgeInsets() : Self.settingsTextViewOutset)
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
                if appearance != .standard {
                    Text(placeholder)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .settingsText(.bodyS)
                        .allowsHitTesting(false)
                } else {
                    Text(placeholder)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .font(Theme.fonts.bodyMMedium)
                        .padding(.leading, 6)
                        .padding(.top, isMacOS ? 0 : 8)
                }
            }

            if let accessory {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(accessory)
                            .foregroundStyle(Theme.colors.textTertiary)
                            .font(Theme.fonts.caption12)
                    }
                }
            }
        }
    }

    private var settingsBorderColor: Color {
        if let isValid, isValid {
            return Theme.colors.alertSuccess
        }
        return (error != nil && error != .empty) ? Theme.colors.alertError : Theme.colors.borderNormal
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
                .foregroundStyle(Theme.colors.textTertiary)
        }
    }
}
