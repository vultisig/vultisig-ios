//
//  CommonTextField.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/08/2025.
//

import SwiftUI

struct CommonTextField<TrailingView: View>: View {
    @Environment(\.isEnabled) var isEnabled
    @Binding var text: String
    let label: String?
    let placeholder: String
    var showError: Bool
    let trailingView: () -> TrailingView
    
    init(
        text: Binding<String>,
        label: String? = nil,
        placeholder: String,
        showError: Bool = false,
        @ViewBuilder trailingView: @escaping () -> TrailingView
    ) {
        self._text = text
        self.label = label
        self.placeholder = placeholder
        self.showError = showError
        self.trailingView = trailingView
    }
    
    init(
        text: Binding<String>,
        label: String? = nil,
        placeholder: String
    ) where TrailingView == EmptyView {
        self.init(text: text, label: label, placeholder: placeholder, trailingView: { EmptyView() })
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label {
                Text(label)
                    .foregroundColor(Theme.colors.textPrimary)
                    .font(Theme.fonts.bodySMedium)
            }
            
            HStack {
                TextField(placeholder.localized, text: $text)
                    .font(Theme.fonts.bodyMRegular)
                    .foregroundColor(Theme.colors.textPrimary)
                    .submitLabel(.done)
                    .colorScheme(.dark)
                    .frame(maxWidth: .infinity)
                
                clearButton
                    .showIf(isEnabled)
                trailingView()
            }
            .frame(height: 56)
            .font(Theme.fonts.bodyMMedium)
            .padding(.horizontal, 12)
            .background(Theme.colors.bgSecondary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 1)
            )
            .autocorrectionDisabled()
            .borderlessTextFieldStyle()
            .padding(1)
        }
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
    
    var borderColor: Color {
        showError ? Theme.colors.alertError : Theme.colors.border
    }
}
