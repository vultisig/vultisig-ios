//
//  StyledFloatingPointField.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import Foundation
import SwiftUI

struct StyledFloatingPointField<Value: BinaryFloatingPoint & Codable>: View {
    let placeholder: String
    @Binding var value: Value
    let format: FloatingPointFormatStyle<Value>
    
    @Binding var isValid: Bool
    var isOptional: Bool = false
    
    @State private var localIsValid: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(placeholder)\(optionalMessage)")
                    .font(.body14MontserratMedium)
                    .foregroundColor(.neutral0)
                if !localIsValid {
                    Text("*")
                        .font(.body14MontserratMedium)
                        .foregroundColor(.red)
                }
            }
            
            TextField(placeholder.capitalized, value: customBinding, format: format)
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .submitLabel(.done)
                .padding(12)
                .background(Color.blue600)
                .cornerRadius(12)
                .borderlessTextFieldStyle()
                .onAppear {
                    localIsValid = isValid
                    validate(value)
                }
#if os(iOS)
                .keyboardType(.decimalPad)
#endif
            
        }
    }
    
    var customBinding: Binding<Value> {
        Binding<Value>(
            get: { value },
            set: { newValue in
                value = newValue
                validate(newValue)
            }
        )
    }
    
    var optionalMessage: String {
        if isOptional {
            return " (optional)"
        }
        return ""
    }
    
    private func validate(_ newValue: Value) {
        if isOptional {
            isValid = String(describing: newValue).isEmpty || newValue >= 0
        } else {
            isValid = !String(describing: newValue).isEmpty && newValue > 0
        }
        localIsValid = isValid
    }
}
