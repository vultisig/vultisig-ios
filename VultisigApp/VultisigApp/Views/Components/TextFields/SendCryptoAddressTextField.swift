//
//  AddressTextField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI
import OSLog
import UniformTypeIdentifiers

struct SendCryptoAddressTextField: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var sendCryptoViewModel: SendCryptoViewModel

    var body: some View {
        VStack(spacing: 16) {
            container
            
            if sendCryptoViewModel.showAddressAlert {
                errorText
            }
            
            AddressFieldAccessoryStack(
                coin: tx.coin,
                onResult: { handle(addressResult: $0) }
            )
        }
    }
    
    var content: some View {
        field
    }
    
    var overlay: some View {
        ZStack {
            Theme.colors.bgButtonPrimary.opacity(0.2)
                .frame(height: 48)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cornerRadius(10)
            
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Theme.colors.bgButtonPrimary, style: StrokeStyle(lineWidth: 1, dash: [10]))
                .padding(5)
            
            Text(NSLocalizedString("dropFileHere", comment: ""))
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.textPrimary)
        }
    }
    
    func handle(addressResult: AddressResult?) {
        guard let addressResult else { return }
        tx.toAddress = addressResult.address
        
        if let amount = addressResult.amount, amount.isNotEmpty {
            tx.amount = amount
            sendCryptoViewModel.convertToFiat(newValue: amount, tx: tx)
        }
        
        if let memo = addressResult.memo, memo.isNotEmpty {
            tx.memo = memo
        } else {
            tx.memo = .empty
        }

        DebounceHelper.shared.debounce {
            validateAddress(addressResult.address)
        }

    }
    
    var errorText: some View {
        Text(NSLocalizedString(sendCryptoViewModel.errorMessage, comment: ""))
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.alertWarning)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    func validateAddress(_ newValue: String) {
        sendCryptoViewModel.validateAddress(tx: tx, address: newValue)
    }
    
    func getButton(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(Theme.fonts.bodyLMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.colors.bgTertiary, lineWidth: 1)
            )
            .padding(1)
    }
}

#Preview {
    SendCryptoAddressTextField(tx: SendTransaction(), sendCryptoViewModel: SendCryptoViewModel())
}

