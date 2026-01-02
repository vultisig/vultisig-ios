//
//  SwapCryptoAmountTextField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-25.
//

import SwiftUI

struct SwapCryptoAmountTextField: View {
    @Binding var amount: String
    
    var onChange: (String) async -> Void
    
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
            .foregroundColor(Theme.colors.textPrimary)
    }
    
    var field: some View {
        let customBiding = Binding<String>(
            get: { amount },
            set: {
                // Don't validate or convert here - just save what the user typed
                amount = $0
                                
                DebounceHelper.shared.debounce(delay: 3) {
                    Task { await onChange(amount) }
                }
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
            .foregroundColor(isEnabled ? Theme.colors.textPrimary : Theme.colors.textSecondary)
            .multilineTextAlignment(.trailing)
    }
}

#Preview {
    SwapCryptoAmountTextField(
        amount: .constant(.empty),
        onChange: { _ in }
    )
    .environmentObject(SettingsViewModel())
}
