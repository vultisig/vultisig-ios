//
//  ReferralTextField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-26.
//

import SwiftUI

struct ReferralTextField: View {
    @Binding var text: String
    let placeholderText: String
    let action: ReferralTextFieldAction
    @Binding var errorMessage: String?

    var showSuccess: Bool
    var isDisabled = false

    init(
        text: Binding<String>,
        placeholderText: String,
        action: ReferralTextFieldAction,
        errorMessage: Binding<String?> = .constant(nil),
        showSuccess: Bool = false,
        isDisabled: Bool = false
    ) {
        self._text = text
        self.placeholderText = placeholderText
        self.action = action
        self._errorMessage = errorMessage
        self.showSuccess = showSuccess
        self.isDisabled = isDisabled
    }

    var body: some View {
        textField
            .onChange(of: text) { _, newValue in
                sanitizeText(newValue)
            }
    }

    var textField: some View {
        CommonTextField(
            text: $text,
            placeholder: placeholderText,
            error: $errorMessage
        ) {
            HStack {
                actionButton
            }
        }
        .disabled(isDisabled)
    }

    var actionButton: some View {
        ZStack {
            switch action {
            case .Paste:
                pasteButton
            case .Copy:
                copyButton
            case .None:
                EmptyView()
            }
        }
        .font(Theme.fonts.bodyMRegular)
        .foregroundColor(Theme.colors.textPrimary)
    }

    var copyButton: some View {
        Button {
            handleCopyCode()
        } label: {
            Icon(named: "copy", color: Theme.colors.textPrimary, size: 20)
        }
    }

    var pasteButton: some View {
        Button {
            handlePasteCode()
        } label: {
            Icon(named: "clipboard-paste", color: Theme.colors.textPrimary, size: 20)
        }
    }

    private func clearCode() {
        text = ""
    }

    // Based on thorname docs
    // https://docs.thorchain.org/how-it-works/thorchain-name-service#overview
    private func sanitizeText(_ text: String) {
        let allowedCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_+"))
        self.text = String(text.unicodeScalars.filter { allowedCharacterSet.contains($0) })
    }
}

#Preview {
    ReferralTextField(
        text: .constant("ABCD"),
        placeholderText: "enterUpto4Characters",
        action: .Copy,
        errorMessage: .constant(nil)
    )
}
