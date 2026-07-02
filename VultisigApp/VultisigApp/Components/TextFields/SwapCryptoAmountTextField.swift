//
//  SwapCryptoAmountTextField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-25.
//

import SwiftUI

struct SwapCryptoAmountTextField: View {
    @Binding var amount: String

    var onChange: (_ oldValue: String, _ newValue: String) async -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.colors.bgSurface1)
    }

    var content: some View {
        textField
    }

    var textField: some View {
        field
            .font(Theme.fonts.bodyLMedium)
            .foregroundStyle(Theme.colors.textPrimary)
    }

    var field: some View {
        let customBiding = Binding<String>(
            get: { amount },
            set: { newValue in
                // Don't validate or convert here - just save what the user typed.
                // Report every keystroke immediately; the quote-fetch path owns
                // debounce timing, so the field stays a dumb input. The old value
                // is passed alongside so callers can tell a paste (multi-char
                // jump) from free typing and skip the debounce for the former.
                let oldValue = amount
                amount = newValue
                Task { await onChange(oldValue, newValue) }
            }
        )

        return container(customBiding)
    }

    func content(_ customBiding: Binding<String>) -> some View {
        TextField(NSLocalizedString("0", comment: "").capitalized, text: customBiding)
            .maxLength(customBiding)
            .submitLabel(.next)
            .disableAutocorrection(true)
            .textFieldStyle(TappableTextFieldStyle())
            .borderlessTextFieldStyle()
            .foregroundStyle(isEnabled ? Theme.colors.textPrimary : Theme.colors.textSecondary)
            .multilineTextAlignment(.trailing)
    }
}

#Preview {
    SwapCryptoAmountTextField(
        amount: .constant(.empty),
        onChange: { _, _ in }
    )
    .environmentObject(SettingsViewModel())
}

#if os(iOS)
import SwiftUI

extension SwapCryptoAmountTextField {
    func container(_ customBiding: Binding<String>) -> some View {
        content(customBiding)
            .textInputAutocapitalization(.never)
            .keyboardType(.decimalPad)
            .textContentType(.oneTimeCode)
    }
}
#endif

#if os(macOS)
import SwiftUI

extension SwapCryptoAmountTextField {
    func container(_ customBiding: Binding<String>) -> some View {
        content(customBiding)
    }
}
#endif
