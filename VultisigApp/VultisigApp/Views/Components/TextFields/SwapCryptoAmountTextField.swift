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
            .background(Color.blue600)
    }
    
    var content: some View {
        textField
    }
    
    var textField: some View {
        field
            .font(.body20MenloBold)
            .foregroundColor(.neutral0)
    }
    
    var field: some View {
        let customBiding = Binding<String>(
            get: { amount },
            set: {
                let newValue = $0.toDecimal().formatDecimalToLocale()
                
                guard amount != newValue else { return }
                amount = newValue
                
                DebounceHelper.shared.debounce(delay: 1.5) {
                    Task { await onChange(newValue) }
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
            .foregroundColor(isEnabled ? .neutral0 : .neutral300)
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
