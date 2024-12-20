//
//  StyledFloatingPointField.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import Foundation
import SwiftUI

struct StyledFloatingPointField: View {
    let placeholder: String
    @Binding var value: Double
    let format: FloatingPointFormatStyle<Double>
    
    @Binding var isValid: Bool
    var isOptional: Bool = false
    
    @State private var localIsValid: Bool = true
    
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
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
        TextField(placeholder.capitalized, text: Binding<String>(
            get: {
                String(describing: value).formatCurrencyInverse(settingsViewModel.selectedCurrency)
            },
            set: { newValue in
                let newString = newValue.formatCurrency(settingsViewModel.selectedCurrency)
                
                guard let newDouble = Double(newString), value != newDouble else { return }
                value = newDouble
            }))
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .submitLabel(.done)
            .padding(12)
            .background(Color.blue600)
            .cornerRadius(12)
            .borderlessTextFieldStyle()
            .onChange(of: value) { oldValue, newValue in
                validate(newValue)
            }
            .onAppear {
                localIsValid = isValid
                validate(value)
            }
    }
    
    var optionalMessage: String {
        if isOptional {
            return " (optional)"
        }
        return ""
    }
    
    private func validate(_ newValue: Double) {
        if isOptional {
            isValid = newValue >= 0
        } else {
            isValid = newValue > 0
        }
        localIsValid = isValid
    }
}
