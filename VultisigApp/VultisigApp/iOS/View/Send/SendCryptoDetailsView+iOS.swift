//
//  SendCryptoDetailsView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(iOS)
import SwiftUI

extension SendCryptoDetailsView {
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    
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
//            fields
            tabs
            buttonContainer
                .background(getButtonBackground())
                .offset(y: -0.9*CGFloat(keyboardObserver.keyboardHeight))
                .animation(.easeInOut, value: keyboardObserver.keyboardHeight)
        }
    }
    
    var buttonContainer: some View {
        button
            .padding(.horizontal, 16)
            .padding(.bottom, idiom == .pad ? 30 : 0)
    }
    
    var fields: some View {
        ScrollViewReader { value in
            ScrollView {
                VStack(spacing: 18) {
                    coinSelector
                    fromField
                    toField
                    
                    if tx.coin.isNativeToken || tx.coin.chainType == .Cosmos || tx.coin.ticker == "TCY" {
                        memoField
                    }
                    
                    amountField
                        .textInputAutocapitalization(.never)
                        .keyboardType(.decimalPad)

                    amountFiatField
                    
                    if !tx.coin.isNativeToken {
                        balanceNativeTokenField
                    }
                    
                    getSummaryCell(leadingText: NSLocalizedString("networkFee", comment: ""), trailingText: "\(tx.gasInReadable)(~\(sendCryptoViewModel.feesInReadable(tx: tx, vault: vault)))")
                    
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
            .refreshable {
                await sendCryptoViewModel.loadGasInfoForSending(tx: tx)
                await getBalance()
            }
        }
    }
    
    func setData() {
        keyboardObserver.keyboardHeight = 0
        Task {
            await sendCryptoViewModel.loadGasInfoForSending(tx: tx)
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
