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
    let showError: Bool
    let errorMessage: String
    
    var body: some View {
        VStack(spacing: 8) {
            textField
            
            if showError {
                errorText
            }
        }
    }
    
    var textField: some View {
        HStack {
            TextField(NSLocalizedString(placeholderText, comment: ""), text: $text)
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .submitLabel(.done)
                .colorScheme(.dark)
            
            actionButton
        }
        .frame(height: 56)
        .font(.body16BrockmannMedium)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(getOutlineColor(), lineWidth: 1)
        )
        .autocorrectionDisabled()
        .borderlessTextFieldStyle()
        .padding(1)
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
        .font(.body16Menlo)
        .foregroundColor(.neutral0)
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
            .font(.body14BrockmannMedium)
            .foregroundColor(.invalidRed)
    }
    
    private func clearCode() {
        text = ""
    }
    
    private func getOutlineColor() -> Color {
        if showError {
            Color.invalidRed
        } else {
            Color.blue200
        }
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
