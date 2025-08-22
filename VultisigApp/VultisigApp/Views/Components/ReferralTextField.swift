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
    var showError: Bool = false
    var errorMessage: String = .empty
    
    var showSuccess: Bool = false
    var isErrorLabelVisible: Bool = true
    var isDisabled = false
    
    var body: some View {
        VStack(spacing: 8) {
            textField
            
            if isErrorLabelVisible && showError {
                errorText
            }
        }
        .onChange(of: text) { _, newValue in
            sanitizeText(newValue)
        }
    }
    
    var textField: some View {
        CommonTextField(text: $text, placeholder: placeholderText) {
            HStack {
                actionButton
            }
        }
    }
    
    var actionButton: some View {
        ZStack {
            switch action {
            case .Paste:
                pasteButton
            case .Copy:
                copyButton
            case .Clear:
                clearButton
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
            Image(systemName: "square.on.square")
        }
    }
    
    var pasteButton: some View {
        Button {
            handlePasteCode()
        } label: {
            Image(systemName: "doc.on.clipboard")
        }
    }
    
    var clearButton: some View {
        Button {
            clearCode()
        } label: {
            Image(systemName: "xmark")
        }
        .opacity(text.isEmpty ? 0 : 1)
    }
    
    var errorText: some View {
        Text(NSLocalizedString(errorMessage, comment: ""))
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.alertError)
    }
    
    private func clearCode() {
        text = ""
    }
    
    private func getOutlineColor() -> Color {
        if showSuccess {
            Theme.colors.alertInfo
        } else if showError {
            Theme.colors.alertError
        } else {
            Theme.colors.border
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
        showError: false,
        errorMessage: ""
    )
}
