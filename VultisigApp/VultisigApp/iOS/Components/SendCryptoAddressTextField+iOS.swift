//
//  SendCryptoAddressTextField+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(iOS)
import SwiftUI

extension SendCryptoAddressTextField {
    var container: some View {
        content
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textPrimary)
            .frame(height: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.colors.bgSecondary)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(sendCryptoViewModel.showAddressAlert ? Theme.colors.alertWarning : Theme.colors.bgTertiary, lineWidth: 1)
            )
            .padding(1)
    }
    
    var field: some View {
        ScrollView(.horizontal, showsIndicators: false) {
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
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textPrimary)
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
            .keyboardType(.default)
            .textInputAutocapitalization(.never)
            .textContentType(.oneTimeCode)
            .frame(minWidth: 200)
            .frame(height: 48)
        }
        .padding(.horizontal, 12)
    }
}
#endif
