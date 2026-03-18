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
    var maxLengthSize: Int
    @Binding var isValid: Bool
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

            TextField(placeholder.capitalized, text: customBinding)
                .font(Theme.fonts.bodyMRegular)
                .foregroundColor(Theme.colors.textPrimary)
                .submitLabel(.done)
                .padding(12)
                .background(Theme.colors.bgSurface1)
                .cornerRadius(12)
                .borderlessTextFieldStyle()
                .maxLength(customBinding, maxLengthSize)
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
        if isOptional {
            isValid = newValue.isEmpty || !newValue.trimmingCharacters(in: .whitespaces).isEmpty
        } else {
            isValid = !newValue.trimmingCharacters(in: .whitespaces).isEmpty
        }
        localIsValid = isValid
    }
}
