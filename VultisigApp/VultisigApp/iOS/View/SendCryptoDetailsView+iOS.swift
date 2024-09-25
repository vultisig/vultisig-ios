//
//  SendCryptoDetailsView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(iOS)
import SwiftUI

extension SendCryptoDetailsView {
    var container: some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    
                    Button {
                        hideKeyboard()
                    } label: {
                        Text(NSLocalizedString("done", comment: "Done"))
                    }
                }
            }
    }
    
    var view: some View {
        VStack {
            fields
            button
        }
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
                    
                    Spacer()
                        .frame(height: keyboardObserver.keyboardHeight)
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: keyboardObserver.keyboardHeight) { oldValue, newValue in
                scrollToField(value)
            }
        }
    }
    
    func setData() {
        keyboardObserver.keyboardHeight = 0
        
        Task {
            isLoading = true
            await getBalance()
            isLoading = false
        }
    }
    
    private func scrollToField(_ value: ScrollViewProxy) {
        withAnimation {
            value.scrollTo(focusedField, anchor: .top)
        }
    }
}
#endif
