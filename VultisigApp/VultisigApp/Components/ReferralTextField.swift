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
    var showInvalid: Bool
    var isDisabled = false
    let appearance: CommonTextFieldAppearance

    init(
        text: Binding<String>,
        placeholderText: String,
        action: ReferralTextFieldAction,
        errorMessage: Binding<String?> = .constant(nil),
        showSuccess: Bool = false,
        showInvalid: Bool = false,
        isDisabled: Bool = false,
        appearance: CommonTextFieldAppearance = .settingsCode
    ) {
        self._text = text
        self.placeholderText = placeholderText
        self.action = action
        self._errorMessage = errorMessage
        self.showSuccess = showSuccess
        self.showInvalid = showInvalid
        self.isDisabled = isDisabled
        self.appearance = appearance
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
            error: $errorMessage,
            isValid: .constant(validation),
            appearance: appearance
        ) {
            HStack {
                actionButton
            }
        }
        .disabled(isDisabled)
    }

    private var validation: Bool? {
        if showSuccess { return true }
        return showInvalid ? false : nil
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
        .foregroundStyle(Theme.colors.textPrimary)
    }

    var copyButton: some View {
        Button {
            handleCopyCode()
        } label: {
            Icon(.copies3Filled, color: Theme.colors.textPrimary, size: 20)
        }
    }

    var pasteButton: some View {
        Button {
            handlePasteCode()
        } label: {
            Icon(.copies3Filled, color: Theme.colors.textPrimary, size: 20)
        }
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

#if os(iOS)
import SwiftUI

extension ReferralTextField {
    func handleCopyCode() {
        let pasteboard = UIPasteboard.general
        pasteboard.string = text
    }

    func handlePasteCode() {
        if let clipboardContent = UIPasteboard.general.string {
            text = clipboardContent
        }
    }
}
#endif

#if os(macOS)
import SwiftUI

extension ReferralTextField {
    func handleCopyCode() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func handlePasteCode() {
        let pasteboard = NSPasteboard.general
        if let clipboardContent = pasteboard.string(forType: .string) {
            text = clipboardContent
        }
    }
}
#endif
