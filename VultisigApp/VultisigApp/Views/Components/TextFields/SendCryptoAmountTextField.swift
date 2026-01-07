//
//  SendCryptoAmountTextField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct SendCryptoAmountTextField: View {
    @Binding var amount: String
    
    var onChange: (String) async -> Void
    var onMaxPressed: (() -> Void)?
    
    @Environment(\.isEnabled) var isEnabled
    
    var body: some View {
        container
    }
    
    var textField: some View {
        TextField(NSLocalizedString("0", comment: "").capitalized, text: Binding<String>(
            get: { amount },
            set: {
                let newValue = $0
                
                guard amount != newValue else { return }
                amount = newValue
                
                DebounceHelper.shared.debounce {
                    Task { await onChange(newValue) }
                }
            }
        ))
        .borderlessTextFieldStyle()
        .font(Theme.fonts.largeTitle)
        .disableAutocorrection(true)
        .textFieldStyle(TappableTextFieldStyle())
        .foregroundColor(isEnabled ? Theme.colors.textPrimary : Theme.colors.textSecondary)
        .maxLength(Binding<String>(
            get: { amount },
            set: {
                let newValue = $0
                
                guard amount != newValue else { return }
                amount = newValue
                
                DebounceHelper.shared.debounce {
                    Task { await onChange(newValue) }
                }
            }
        ))
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
    
    var maxButton: some View {
        Button { onMaxPressed?() } label: {
            Text(NSLocalizedString("max", comment: "").uppercased())
                .font(Theme.fonts.bodyMMedium)
                .foregroundColor(Theme.colors.textPrimary)
                .frame(width: 40, height: 40)
        }
    }
    
    var showButton: Bool {
        return onMaxPressed != nil
    }
}

#Preview {
    SendCryptoAmountTextField(
        amount: .constant(.empty), 
        onChange: { _ in },
        onMaxPressed: { }
    )
    .environmentObject(SettingsViewModel())
}
