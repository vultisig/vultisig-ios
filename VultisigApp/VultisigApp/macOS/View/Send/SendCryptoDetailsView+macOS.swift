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
            buttonContainer
                .padding(.horizontal, 8)
                .padding(.vertical, -12)
        }
    }
    
    var buttonContainer: some View {
        button
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
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
