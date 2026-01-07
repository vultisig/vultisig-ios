//
//  StyledIntegerField.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import SwiftUI

struct StyledIntegerField<Value: BinaryInteger & Codable>: View {
    let placeholder: String
    @Binding var value: Value
    let format: IntegerFormatStyle<Value>
    
    @Binding var isValid: Bool
    var isEnabled: Bool = true
    var isOptional: Bool = false
    
    @State private var localIsValid: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(placeholder)\(optionalMessage)")
                    .font(Theme.fonts.bodySMedium)
                    .foregroundColor(Theme.colors.textPrimary)
                if !localIsValid {
                    Text("*")
                        .font(Theme.fonts.bodySMedium)
                        .foregroundColor(.red)
                }
            }
            
            container
        }
    }
    
    var textField: some View {
        TextField(placeholder.capitalized, value: customBinding, format: format)
            .font(Theme.fonts.bodyMRegular)
            .foregroundColor(foregroundColor)
            .submitLabel(.done)
            .padding(12)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(12)
            .borderlessTextFieldStyle()
            .onAppear {
                localIsValid = isValid
                validate(String(describing: value))
            }
            .disabled(!isEnabled)
    }

    var foregroundColor: Color {
        isEnabled ? Theme.colors.textPrimary : Theme.colors.textTertiary
    }

    var customBinding: Binding<Value> {
        Binding<Value>(
            get: { value },
            set: { newValue in
                value = newValue
                validate(String(describing: newValue))
            }
        )
    }
    
    var optionalMessage: String {
        if isOptional {
            return " (optional)"
        }
        return ""
    }
    
    private func validate(_ newValue: String) {
        if isOptional {
            isValid = newValue.isEmpty || (Int64(newValue) ?? .zero >= .zero)
        } else {
            isValid = !newValue.isEmpty && (Int64(newValue) ?? .zero > .zero)
        }
        localIsValid = isValid
    }
}
