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
        ZStack(alignment: .bottom) {
            fields
            
            button
                .background(getButtonBackground())
                .offset(y: -0.9*CGFloat(keyboardObserver.keyboardHeight))
                .animation(.easeInOut, value: keyboardObserver.keyboardHeight)
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
            await getBalance()
        }
    }
    
    private func scrollToField(_ value: ScrollViewProxy) {
        withAnimation {
            value.scrollTo(focusedField, anchor: .top)
        }
    }
    
    private func getButtonBackground() -> Color {
        if keyboardObserver.keyboardHeight == 0 {
            return Color.clear
        } else {
            return Color.backgroundBlue
        }
    }
}
#endif
