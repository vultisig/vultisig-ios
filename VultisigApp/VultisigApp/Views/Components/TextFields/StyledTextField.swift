//
//  StyledTextField.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import Foundation
import SwiftUI

struct StyledTextField: View {
    let placeholder: String
    @Binding var text: String
    
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
            
            TextField(placeholder.capitalized, text: customBinding)
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .submitLabel(.done)
                .padding(12)
                .background(Color.blue600)
                .cornerRadius(12)
                .onAppear {
                    localIsValid = isValid
                    validate(text)
                }
        }
    }
    
    var customBinding: Binding<String> {
        Binding<String>(
            get: { text },
            set: { newValue in
                text = newValue
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
    
    private func validate(_ newValue: String) {
        print("Validating text: \(newValue)")
        if isOptional {
            isValid = newValue.isEmpty || !newValue.trimmingCharacters(in: .whitespaces).isEmpty
        } else {
            isValid = !newValue.trimmingCharacters(in: .whitespaces).isEmpty
        }
        localIsValid = isValid
        print("Validation result: \(isValid)")
    }
}
