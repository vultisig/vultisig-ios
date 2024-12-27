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
    
    @Environment(\.isEnabled) private var isEnabled
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    var body: some View {
        HStack(spacing: 0) {
            container
            
            if showButton {
                maxButton
            }
        }
        .font(.body12Menlo)
        .foregroundColor(.neutral0)
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(10)
    }
    
    var container: some View {
        TextField(NSLocalizedString("enterAmount", comment: "").capitalized, text: Binding<String>(
            get: { amount },
            set: {
                let newValue = $0.formatCurrency()
                
                guard amount != newValue else { return }
                amount = newValue
                
                DebounceHelper.shared.debounce {
                    Task { await onChange(newValue) }
                }
            }
        ))
        .borderlessTextFieldStyle()
        .font(.body16MenloBold)
        .submitLabel(.next)
        .disableAutocorrection(true)
        .textFieldStyle(TappableTextFieldStyle())
        .foregroundColor(isEnabled ? .neutral0 : .neutral300)
        .maxLength(Binding<String>(
            get: { amount },
            set: {
                let newValue = $0.formatCurrency()
                
                guard amount != newValue else { return }
                amount = newValue
                
                DebounceHelper.shared.debounce {
                    Task { await onChange(newValue) }
                }
            }
        ))
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
