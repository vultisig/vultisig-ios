//
//  TransactionMemoHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-08.
//

import SwiftUI

struct TransactionMemoHeader: View {
    @ObservedObject var transactionMemoViewModel: TransactionMemoViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        HStack {
            leadingAction
            Spacer()
            text
            Spacer()
            leadingAction.opacity(0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 40)
        .padding(.top, 8)
    }
    
    var leadingAction: some View {
        let isDone = transactionMemoViewModel.currentIndex==5
        
        return Button {
            handleBackTap()
        } label: {
            NavigationBlankBackButton()
        }
        .opacity(isDone ? 0 : 1)
        .disabled(isDone)
    }
    
    var text: some View {
        Text(NSLocalizedString(transactionMemoViewModel.currentTitle, comment: "SendCryptoView title"))
            .foregroundColor(.neutral0)
            .font(.title3)
    }
    
    private func handleBackTap() {
        guard transactionMemoViewModel.currentIndex>1 else {
            dismiss()
            return
        }
        
        transactionMemoViewModel.handleBackTap()
    }
}

#Preview {
    TransactionMemoHeader(transactionMemoViewModel: TransactionMemoViewModel())
}
