//
//  CommonTextField.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/08/2025.
//

import SwiftUI

struct CommonTextField: View {
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                TextField(placeholder.localized, text: $text)
                    .font(Theme.fonts.bodyMRegular)
                    .foregroundColor(Theme.colors.textPrimary)
                    .submitLabel(.done)
                    .colorScheme(.dark)
                
                clearButton
            }
        }
        .frame(height: 56)
        .font(Theme.fonts.bodyMMedium)
        .padding(.horizontal, 12)
        .background(Theme.colors.bgSecondary)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
        .autocorrectionDisabled()
        .borderlessTextFieldStyle()
        .padding(1)
    }
    
    var clearButton: some View {
        Button {
            text = ""
        } label: {
            Icon(
                named: "circle-x-fill",
                color: Theme.colors.textExtraLight,
                size: 16
            )
        }
        .opacity(text.isEmpty ? 0 : 1)
    }
}
