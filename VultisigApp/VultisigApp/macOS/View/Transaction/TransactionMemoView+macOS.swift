//
//  TransactionMemoView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(macOS)
import SwiftUI

extension TransactionMemoView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationBarBackButtonHidden(transactionMemoViewModel.currentIndex != 1 ? true : false)
    }
    
    var main: some View {
        VStack {
            headerMac
            layers
        }
    }
    
    var headerMac: some View {
        TransactionMemoHeader(transactionMemoViewModel: transactionMemoViewModel)
    }
    
    var layers: some View {
        ZStack {
            Background()
            view
            
            if transactionMemoViewModel.isLoading || transactionMemoVerifyViewModel.isLoading {
                loader
            }
        }
    }
}
#endif
