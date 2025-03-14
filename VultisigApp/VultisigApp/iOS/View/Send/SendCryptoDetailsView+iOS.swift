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
            fields
            
            button
                .background(getButtonBackground())
                .offset(y: -0.9*CGFloat(keyboardObserver.keyboardHeight))
                .animation(.easeInOut, value: keyboardObserver.keyboardHeight)
        }
    }
    
    var button: some View {
        Button {
            Task{
                await validateForm()
            }
        } label: {
            HStack {
                FilledButton(
                    title: sendCryptoViewModel.isLoading ? "loadingDetails" : "continue",
                    textColor: sendCryptoViewModel.isLoading ? .textDisabled : .blue600,
                    background: sendCryptoViewModel.isLoading ? .buttonDisabled : .turquoise600,
                    showLoader: sendCryptoViewModel.isLoading
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, idiom == .pad ? 30 : 0)
        .disabled(sendCryptoViewModel.isLoading)
    }
    
    var fields: some View {
        ScrollViewReader { value in
            ScrollView {
                VStack(spacing: 18) {
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
