//
//  TransactionMemoView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(iOS)
import SwiftUI

extension TransactionMemoView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationBarBackButtonHidden(transactionMemoViewModel.currentIndex != 1 ? true : false)
        .navigationTitle(NSLocalizedString(transactionMemoViewModel.currentTitle, comment: "SendCryptoView title"))
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(.keyboard)
        .toolbar {
            if transactionMemoViewModel.currentIndex != 1 {
                ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                    backButton
                }
            }
        }
    }
    
    var main: some View {
        layers
    }
    
    var layers: some View {
        ZStack {
            Background()
            view
            
            if transactionMemoViewModel.isLoading || transactionMemoVerifyViewModel.isLoading {
                loader
            }
        }
        .onTapGesture {
            hideKeyboard()
        }
    }
    
    var backButton: some View {
        let isDone = transactionMemoViewModel.currentIndex==5
        
        return Button {
            transactionMemoViewModel.handleBackTap()
        } label: {
            NavigationBlankBackButton()
                .offset(x: -8)
        }
        .opacity(isDone ? 0 : 1)
        .disabled(isDone)
    }
}
#endif
