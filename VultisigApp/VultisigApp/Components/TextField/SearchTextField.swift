//
//  SearchTextField.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 01/08/2025.
//

import SwiftUI

struct SearchTextField: View {
    @Binding var value: String
    @Binding var isFocused: Bool
    let showPasteButton: Bool
    @FocusState var focusedState: Bool

    init(value: Binding<String>, isFocused: Binding<Bool> = .constant(false), showPasteButton: Bool = false) {
        self._value = value
        self._isFocused = isFocused
        self.showPasteButton = showPasteButton
    }

    var showClearButton: Bool {
        value.isNotEmpty
    }

    var body: some View {
        HStack(spacing: 0) {
            Icon(
                named: "magnifying-glass",
                color: Theme.colors.textSecondary,
                size: 16
            )
            TextField(NSLocalizedString("search", comment: "Search"), text: $value)
                .font(Theme.fonts.bodyMMedium)
                .foregroundColor(Theme.colors.textPrimary)
                .disableAutocorrection(true)
                .borderlessTextFieldStyle()
                .colorScheme(.dark)
                .padding(.horizontal, 8)
                .focused($focusedState)

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
        .frame(height: 44)
        .padding(.horizontal, 12)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(99)
        .onChange(of: focusedState) { _, newValue in
            isFocused = newValue
        }
        .onChange(of: isFocused) { _, newValue in
            focusedState = newValue
        }
    }

    var clearButton: some View {
        Button {
            value = .empty
            isFocused = false
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(Theme.colors.textSecondary)
        }
        .buttonStyle(.plain)
    }

    var pasteButton: some View {
        Button {
            guard let pasted = ClipboardManager.pasteFromClipboard() else { return }
            value = pasted
        } label: {
            Icon(named: "copy-2", color: Theme.colors.textSecondary, size: 20)
        }
        .buttonStyle(.plain)
    }
}
