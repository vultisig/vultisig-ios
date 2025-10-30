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
    @Binding var isSecure: Bool
    @Binding var error: String?
    let isScrollable: Bool
    let labelStyle: TextFieldLabelStyle
    
    let trailingView: () -> TrailingView
    
    init(
        text: Binding<String>,
        label: String? = nil,
        placeholder: String,
        isSecure: Binding<Bool> = .constant(false),
        error: Binding<String?> = .constant(nil),
        isScrollable: Bool = false,
        labelStyle: TextFieldLabelStyle = .primary,
        @ViewBuilder trailingView: @escaping () -> TrailingView
    ) {
        self._text = text
        self.label = label
        self.placeholder = placeholder
        self._isSecure = isSecure
        self._error = error
        self.isScrollable = isScrollable
        self.trailingView = trailingView
        self.labelStyle = labelStyle
    }
    
    init(
        text: Binding<String>,
        label: String? = nil,
        placeholder: String,
        isSecure: Binding<Bool> = .constant(false),
        error: Binding<String?> = .constant(nil),
        isScrollable: Bool = false,
        labelStyle: TextFieldLabelStyle = .primary,
    ) where TrailingView == EmptyView {
        self.init(
            text: text,
            label: label,
            placeholder: placeholder,
            isSecure: isSecure,
            error: error,
            isScrollable: isScrollable,
            labelStyle: labelStyle,
            trailingView: { EmptyView() }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label {
                Text(label)
                    .foregroundColor(labelColor)
                    .font(labelFont)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    textFieldContainer
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
                
                if let error {
                    Text(error.localized)
                        .foregroundColor(Theme.colors.alertError)
                        .font(Theme.fonts.footnote)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .animation(.easeInOut, value: error)
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
        .buttonStyle(.plain)
        .opacity(text.isEmpty ? 0 : 1)
    }
    
    var borderColor: Color {
        (error != nil && error != .empty) ? Theme.colors.alertError : Theme.colors.border
    }
    
    @ViewBuilder
    var textFieldContainer: some View {
        if isScrollable {
            ScrollView(.horizontal, showsIndicators: false) {
                textField
                    .frame(minWidth: 200)
            }
        } else {
            textField
        }
    }
    
    @ViewBuilder
    var textField: some View {
        Group {
            if isSecure {
                SecureField(placeholder.localized, text: $text)
            } else {
                TextField(placeholder.localized, text: $text)
            }
        }
        .frame(height: 56)
    }
    
    var labelFont: Font {
        switch labelStyle {
        case .primary:
            Theme.fonts.bodySMedium
        case .secondary:
            Theme.fonts.footnote
        }
    }
    
    var labelColor: Color {
        switch labelStyle {
        case .primary:
            Theme.colors.textPrimary
        case .secondary:
            Theme.colors.textExtraLight
        }
    }
    
    enum TextFieldLabelStyle {
        case primary
        case secondary
    }
}
