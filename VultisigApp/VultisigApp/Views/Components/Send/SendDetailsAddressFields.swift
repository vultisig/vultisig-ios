//
//  SendDetailsAddressFields.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-30.
//

import SwiftUI

struct SendDetailsAddressFields: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var viewModel: SendDetailsViewModel
    @ObservedObject var sendCryptoViewModel: SendCryptoViewModel
    @FocusState.Binding var focusedField: Field?
    
    @EnvironmentObject var appViewModel: AppViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            fromField
            toField
        }
    }
    
    var fromField: some View {
        VStack(spacing: 12) {
            Text("from".localized)
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            fromDetailsField
        }
    }
    
    var fromDetailsField: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let vaultName = appViewModel.selectedVault?.name {
                Text(vaultName)
                    .foregroundColor(Theme.colors.textPrimary)
            }
            
            Text(tx.fromAddress)
                .foregroundColor(Theme.colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(Theme.fonts.caption12).padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.colors.bgSurface2, lineWidth: 1)
        )
        .padding(1)
    }
    
    var toField: some View {
        AddressTextField(
            address: $tx.toAddress,
            label: "sendTo".localized,
            coin: tx.coin,
            error: Binding(
                get: { sendCryptoViewModel.showAddressAlert ? sendCryptoViewModel.errorMessage : nil },
                set: { _ in }
            )
        ) {
            handle(addressResult: $0)
        }
        .onChange(of: tx.toAddress) { _, newValue in
            DebounceHelper.shared.debounce {
                validateAddress(newValue)
            }
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
        }
                
        // Attempt to detect and switch chain if address belongs to different chain
        if !tx.toAddress.isEmpty, let vault = appViewModel.selectedVault {
            let detectedCoin = viewModel.detectAndSwitchChain(
                from: tx.toAddress,
                vault: vault,
                currentChain: tx.coin.chain,
                tx: tx
            )
            
            if detectedCoin != nil {
                // Clear previous error
                sendCryptoViewModel.showAddressAlert = false
                sendCryptoViewModel.errorMessage = ""
                sendCryptoViewModel.isValidAddress = true
                
                // Mark address as done and move to amount
                viewModel.addressSetupDone = true
                viewModel.onSelect(tab: .amount)
            }
        }
        
        // Always validate after potential chain switch
        validateAddress(tx.toAddress)
    }
    
    func validateAddress(_ newValue: String) {
        sendCryptoViewModel.validateAddress(tx: tx, address: newValue)
    }
}
