//
//  SearchTextField.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 01/08/2025.
//

import SwiftUI

struct SearchTextField: View {
    enum Appearance {
        case standard
        /// 42 tall with a footnote placeholder and a soft inner glow.
        case settings
    }

    private static var settingsHeight: CGFloat { 42 }
    private static var settingsInnerGlow: Color { Color(hex: "F0F4FC").opacity(0.03) }

    @Binding var value: String
    @Binding var isFocused: Bool
    let showPasteButton: Bool
    let placeholder: String
    let accessibilityIdentifier: String?
    let appearance: Appearance
    @FocusState var focusedState: Bool

    init(
        value: Binding<String>,
        isFocused: Binding<Bool> = .constant(false),
        showPasteButton: Bool = false,
        placeholder: String = "search".localized,
        accessibilityIdentifier: String? = nil,
        appearance: Appearance = .standard
    ) {
        self._value = value
        self._isFocused = isFocused
        self.showPasteButton = showPasteButton
        self.placeholder = placeholder
        self.accessibilityIdentifier = accessibilityIdentifier
        self.appearance = appearance
    }

    var showClearButton: Bool {
        value.isNotEmpty
    }

    var body: some View {
        HStack(spacing: 0) {
            Icon(
                .magnifier,
                color: appearance == .settings ? Theme.colors.textPrimary : Theme.colors.textSecondary,
                size: 16
            )
            textField
                .foregroundStyle(Theme.colors.textPrimary)
                .disableAutocorrection(true)
                .borderlessTextFieldStyle()
                .colorScheme(.dark)
                .padding(.horizontal, 8)
                .focused($focusedState)
                .unwrap(accessibilityIdentifier) { view, id in
                    view.accessibilityIdentifier(id)
                }

            HStack(spacing: 8) {
                clearButton
                    .opacity(showClearButton ? 1 : 0)
                    .allowsHitTesting(showClearButton)
                    .animation(.easeInOut, value: showClearButton)

                pasteButton
                    .showIf(showPasteButton)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: appearance == .settings ? Self.settingsHeight : nil)
        .frame(height: appearance == .settings ? nil : 44)
        .padding(.horizontal, 12)
        .background(background)
        .cornerRadius(Theme.radius.pill)
        .onChange(of: focusedState) { _, newValue in
            isFocused = newValue
        }
        .onChange(of: isFocused) { _, newValue in
            focusedState = newValue
        }
    }

    @ViewBuilder
    private var textField: some View {
        switch appearance {
        case .standard:
            TextField(placeholder, text: $value)
                .font(Theme.fonts.bodyMMedium)
        case .settings:
            TextField(
                placeholder,
                text: $value,
                prompt: Text(placeholder).foregroundStyle(Theme.colors.textTertiary)
            )
            .font(Theme.fonts.footnote)
            .tracking(SettingsTextStyle.footnote.tracking)
        }
    }

    @ViewBuilder
    private var background: some View {
        switch appearance {
        case .standard:
            Theme.colors.bgSurface1
        case .settings:
            Capsule(style: .circular)
                .fill(Theme.colors.bgSurface1.shadow(.inner(color: Self.settingsInnerGlow, radius: 8)))
        }
    }

    var clearButton: some View {
        Button {
            value = .empty
            isFocused = false
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Theme.colors.textSecondary)
        }
        .buttonStyle(.plain)
    }

    var pasteButton: some View {
        Button {
            guard let pasted = ClipboardManager.pasteFromClipboard() else { return }
            value = pasted
        } label: {
            Icon(.clone, color: Theme.colors.textSecondary, size: 20)
        }
        .buttonStyle(.plain)
    }
}
