//
//  StyledFloatingPointField.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import Foundation
import SwiftUI

struct StyledFloatingPointField: View {
    let label: String
    let placeholder: String
    @Binding var value: Decimal
    @Binding var isValid: Bool
    
    var isOptional: Bool = false
    
    @State private var textFieldValue: String = ""
    @State private var localIsValid: Bool = true
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(label)\(optionalMessage)")
                    .font(Theme.fonts.bodySMedium)
                    .foregroundColor(Theme.colors.textPrimary)
                if !localIsValid {
                    Text("*")
                        .font(Theme.fonts.caption10)
                        .foregroundColor(.red)
                }
            }
            
            container
        }
        .id(placeholder)
    }
    
    var textField: some View {
        TextField("", text: $textFieldValue)
            .placeholder(when: textFieldValue.isEmpty) {
                Text(placeholder.capitalized)
                    .foregroundColor(.gray)
            }
            .font(Theme.fonts.bodyMRegular)
            .foregroundColor(Theme.colors.textPrimary)
            .submitLabel(.done)
            .padding(12)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(12)
            .borderlessTextFieldStyle()
            .onChange(of: textFieldValue) { _, newValue in
                updateValue(newValue)
            }
            .onAppear {
                textFieldValue = value.formatDecimalToLocale()
                localIsValid = isValid
            }
            .onChange(of: placeholder) { _, _ in
                textFieldValue = value.formatDecimalToLocale()
                localIsValid = isValid
            }
            .id(placeholder)
    }
    
    private func updateValue(_ newValue: String) {        
        textFieldValue = newValue
        
        if newValue.isValidDecimal() {
            value = newValue.toDecimal()
            validate(value)
        } else {
            value = 0
            validate(value)
        }
    }
    
    private func validate(_ newValue: Decimal) {
        if isOptional {
            isValid = (newValue == 0) || (newValue >= 0)
        } else {
            isValid = newValue > 0
        }
        localIsValid = isValid
    }
    
    var optionalMessage: String {
        return isOptional ? " (optional)" : ""
    }
}

// Placeholder helper stays the same
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            self
            if shouldShow {
                placeholder()
            }
        }
    }
}
