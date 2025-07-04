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
            tabs
                .offset(y: keyboardObserver.keyboardHeight != 0 ? -80 : 0)
            
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
