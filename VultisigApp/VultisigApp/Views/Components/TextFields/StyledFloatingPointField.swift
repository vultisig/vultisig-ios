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
    
    @State private var textFieldValue: String = ""
    @State private var localIsValid: Bool = true
    
    // Determine the decimal separator based on the current locale
    private var decimalSeparator: String {
        return Locale.current.decimalSeparator ?? "."
    }
    
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
            
            container
        }
    }
    
    var textField: some View {
        TextField(placeholder.capitalized, text: $textFieldValue)
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .submitLabel(.done)
            .padding(12)
            .background(Color.blue600)
            .cornerRadius(12)
            .borderlessTextFieldStyle()
            .onChange(of: textFieldValue) { newValue in
                updateValue(newValue)
            }
            .onAppear {
                textFieldValue = formatInitialValue()
                localIsValid = isValid
            }
        }
    
    private func formatInitialValue() -> String {
        // Convert initial value to string using the current locale
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8 // Adjust as needed
        return formatter.string(from: NSNumber(value: Double(value))) ?? ""
    }
    
    private func updateValue(_ newValue: String) {
        // Replace locale-specific decimal separator with standard decimal point
        let standardizedValue = newValue.replacingOccurrences(of: decimalSeparator, with: ".")
        
        // Remove any characters that are not digits or a single decimal point
        let filteredValue = standardizedValue
            .components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .joined()
        
        // Ensure only one decimal point
        let parts = filteredValue.components(separatedBy: ".")
        let processedValue = parts.count > 2
            ? parts[0] + "." + parts[1..<parts.count].joined(separator: "")
            : filteredValue
        
        // Update text field and value
        textFieldValue = processedValue.replacingOccurrences(of: ".", with: decimalSeparator)
        
        // Convert to numeric value
        if let doubleValue = Double(processedValue) {
            value = Value(doubleValue)
            validate(value)
        } else if processedValue.isEmpty || processedValue == decimalSeparator {
            value = 0
        }
    }
    
    private func validate(_ newValue: Value) {
        if isOptional {
            isValid = String(describing: newValue).isEmpty || newValue >= 0
        } else {
            isValid = !String(describing: newValue).isEmpty && newValue > 0
        }
        localIsValid = isValid
    }
    
    var optionalMessage: String {
        return isOptional ? " (optional)" : ""
    }
}
