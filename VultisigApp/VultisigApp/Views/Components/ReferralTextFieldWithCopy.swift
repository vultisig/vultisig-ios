//
//  ReferralTextFieldWithCopy.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-26.
//

import SwiftUI

struct ReferralTextFieldWithCopy: View {
    let placeholderText: String
    @Binding var text: String
    @Binding var showError: Bool
    @Binding var errorMessage: String
    
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
            
            copyButton
        }
        .frame(height: 56)
        .font(.body16BrockmannMedium)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(showError ? Color.invalidRed : Color.blue200, lineWidth: 1)
        )
        .autocorrectionDisabled()
        .borderlessTextFieldStyle()
        .padding(1)
    }
    
    var copyButton: some View {
        Button {
            handleCopyCode()
        } label: {
            Image(systemName: "square.on.square")
        }
    }
    
    var errorText: some View {
        Text(NSLocalizedString(errorMessage, comment: ""))
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.body14BrockmannMedium)
            .foregroundColor(.invalidRed)
    }
    
    private func handleCopyCode() {
        
    }
}

#Preview {
    ReferralTextFieldWithCopy(placeholderText: "enterUpto4Characters", text: .constant("ABCD"), showError: .constant(false), errorMessage: .constant(""))
}
