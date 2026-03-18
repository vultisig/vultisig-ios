//
//  SecureTextField.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/09/2025.
//

import SwiftUI

struct SecureTextField: View {
    @Binding var value: String
    let label: String?
    let placeholder: String?
    @Binding var error: String?
    @Binding var isValid: Bool?

    @State var isSecure: Bool = true

    init(
        value: Binding<String>,
        label: String? = nil,
        placeholder: String?,
        error: Binding<String?>,
        isValid: Binding<Bool?> = .constant(nil)
    ) {
        self._value = value
        self.label = label
        self.placeholder = placeholder
        self._error = error
        self._isValid = isValid
    }

    var body: some View {
        CommonTextField(
            text: $value,
            label: label,
            placeholder: placeholder,
            isSecure: $isSecure,
            error: $error,
            isValid: $isValid,
            trailingView: {
                Button(
                    action: {
                        withAnimation {
                            isSecure.toggle()
                        }
                    },
                    label: {
                        Image(systemName: isSecure ? "eye.slash": "eye")
                            .foregroundColor(Theme.colors.textPrimary)
                    }
                )
                .buttonStyle(.plain)
                .contentTransition(.symbolEffect(.replace))
            }
        )
        #if os(iOS)
            .textInputAutocapitalization(.never)
        #endif
    }
}
