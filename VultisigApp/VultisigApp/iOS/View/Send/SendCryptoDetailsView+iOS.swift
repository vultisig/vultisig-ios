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
            buttonContainer
        }
    }
    
    var buttonContainer: some View {
        button
            .padding(.horizontal, 16)
            .padding(.vertical, idiom == .pad ? 30 : 8)
            .background(keyboardObserver.keyboardHeight == 0 ? .clear : .backgroundBlue)
            .shadow(color: .backgroundBlue, radius: keyboardObserver.keyboardHeight == 0 ? 0 : 15)
    }
    
    
    func setData() {
        keyboardObserver.keyboardHeight = 0
        Task {
            await sendCryptoViewModel.loadGasInfoForSending(tx: tx)
            await getBalance()
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
