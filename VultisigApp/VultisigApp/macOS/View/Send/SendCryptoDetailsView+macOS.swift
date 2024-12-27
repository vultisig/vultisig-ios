//
//  SendCryptoDetailsView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(macOS)
import SwiftUI

extension SendCryptoDetailsView {
    var container: some View {
        content
    }
    
    var view: some View {
        VStack {
            fields
            button
                .padding(.horizontal, 8)
                .padding(.vertical, -12)
        }
    }
    
    var button: some View {
        Button {
            Task{
                await validateForm()
            }
        } label: {
            FilledButton(title: "continue")
        }
        .padding(.horizontal, 40)
        .padding(.top, 20)
        .padding(.bottom, 40)
        .grayscale(sendCryptoViewModel.isLoading ? 1 : 0)
        .disabled(sendCryptoViewModel.isLoading)
    }
    
    var fields: some View {
        ScrollViewReader { value in
            ScrollView {
                VStack(spacing: 16) {
                    coinSelector
                    fromField
                    toField
                    
                    if tx.coin.isNativeToken {
                        memoField
                    }
                    
                    amountField
                    amountFiatField
                    
                    if !tx.coin.isNativeToken {
                        balanceNativeTokenField
                    }
                    
                    getSummaryCell(leadingText: NSLocalizedString("networkFee", comment: ""), trailingText: "\(tx.gasInReadable)(~\(sendCryptoViewModel.feesInReadable(tx: tx, vault: vault)))")
                    
                    if tx.canBeReaped {
                        existentialDepositTextMessage
                    }
                }
                .padding(.horizontal, 16)
                .padding(26)
            }
        }
    }
    
    func setData() {
        Task {
            await getBalance()
        }
    }
}
#endif
