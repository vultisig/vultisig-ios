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
        .font(.body34BrockmannMedium)
        .disableAutocorrection(true)
        .textFieldStyle(TappableTextFieldStyle())
        .foregroundColor(isEnabled ? .neutral0 : .neutral300)
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
        .multilineTextAlignment(.center)
    }
    
    var maxButton: some View {
        Button { onMaxPressed?() } label: {
            Text(NSLocalizedString("max", comment: "").uppercased())
                .font(.body16MenloBold)
                .foregroundColor(.neutral0)
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
