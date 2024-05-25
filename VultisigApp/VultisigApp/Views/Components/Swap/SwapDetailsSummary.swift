//
//  SwapDetailsSummary.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-25.
//

import SwiftUI

struct SwapDetailsSummary: View {
    @ObservedObject var tx: SwapTransaction
    @ObservedObject var swapViewModel: SwapCryptoViewModel
    
    var body: some View {
        content
    }
    
    var content: some View {
        VStack(spacing: 16) {
            
            
            getSummaryCell(leadingText: "gas(auto)", trailingText: String(tx.gas))
            
            if swapViewModel.showFees(tx: tx) {
                getSummaryCell(leadingText: "Estimated Fees", trailingText: swapViewModel.swapFeeString(tx: tx))
            }
            
            if swapViewModel.showDuration(tx: tx) {
                getSummaryCell(leadingText: "Estimated Time", trailingText: swapViewModel.durationString(tx: tx))
            }
            
            if let error = swapViewModel.error {
                Separator()
                getErrorCell(text: error.localizedDescription)
            }
        }
    }
    
    private func getSummaryCell(leadingText: String, trailingText: String) -> some View {
        HStack {
            Text(NSLocalizedString(leadingText, comment: ""))
            Spacer()
            Text(trailingText)
        }
        .font(.body14Menlo)
        .foregroundColor(.neutral0)
    }
    
    private func getErrorCell(text: String) -> some View {
        HStack() {
            Text(text)
                .foregroundColor(.destructive)
                .font(.body12Menlo)
                .multilineTextAlignment(.leading)
                .lineSpacing(4)

            Spacer()
        }
    }
}

#Preview {
    ZStack {
        Background()
        SwapDetailsSummary(tx: SwapTransaction(), swapViewModel: SwapCryptoViewModel())
    }
}
