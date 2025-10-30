//
//  SendCryptoAddressTextField+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

extension SendCryptoAddressTextField {
    var container: some View {
        content
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textPrimary)
            .frame(height: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.colors.bgSecondary)
            .cornerRadius(10)
    }
    
    var field: some View {
        HStack(spacing: 0) {
            TextField(NSLocalizedString("enterAddressHere", comment: "").capitalized, text: Binding<String>(
                get: { tx.toAddress },
                set: { newValue in
                    tx.toAddress = newValue
                    DebounceHelper.shared.debounce {
                        validateAddress(newValue)
                    }
                }
            ))
            .onChange(of: tx.toAddress) { oldValue, newValue in
                Task {
                    await sendCryptoViewModel.loadGasInfoForSending(tx: tx)
                }
            }
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodySMedium)
            .submitLabel(.next)
            .disableAutocorrection(true)
            .borderlessTextFieldStyle()
            .maxLength(Binding<String>(
                get: { tx.toAddress },
                set: { newValue in
                    tx.toAddress = newValue
                    DebounceHelper.shared.debounce {
                        validateAddress(newValue)
                    }
                }
            ))
        }
        .padding(.horizontal, 12)
    }
}
#endif
