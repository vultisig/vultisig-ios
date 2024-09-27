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
        }
        .padding(26)
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
                    
                    getSummaryCell(leadingText: NSLocalizedString("gas(auto)", comment: ""), trailingText: tx.gasInReadable)
                    getSummaryCell(leadingText: NSLocalizedString("Estimated Fees", comment: ""), trailingText: sendCryptoViewModel.feesInReadable(tx: tx, vault: vault))
                    
                    if tx.canBeReaped {
                        existentialDepositTextMessage
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    func setData() {
        Task {
            isLoading = true
            await getBalance()
            isLoading = false
        }
    }
}
#endif
