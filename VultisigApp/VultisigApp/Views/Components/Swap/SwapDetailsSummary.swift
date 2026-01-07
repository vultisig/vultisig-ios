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
    
    @State var showFees: Bool = false
    
    var body: some View {
        content
            .animation(.easeInOut, value: showFees)
    }
    
    var content: some View {
        VStack(spacing: 16) {
            if let providerName = tx.quote?.displayName {
                getSummaryCell(
                    leadingText: "provider",
                    trailingText: providerName
                )
            }
            
            if swapViewModel.showTotalFees(tx: tx) {
                totalFees
            }
            
            otherFees
            
            if let error = swapViewModel.error {
                Separator()
                getErrorCell(text: error.localizedDescription)
            }
        }
        .padding(.top, 8)
    }
    
    var totalFees: some View {
        Button {
            showFees.toggle()
        } label: {
            totalFeesLabel
        }
    }
    
    var totalFeesLabel: some View {
        HStack {
            getSummaryCell(
                leadingText: "totalFee",
                trailingText: "\(swapViewModel.totalFeeString(tx: tx))"
            )
            
            chevron
        }
    }
    
    var chevron: some View {
        Image(systemName: "chevron.up")
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textPrimary)
            .rotationEffect(Angle(degrees: showFees ? 0 : 180))
    }
    
    var otherFees: some View {
        HStack {
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Theme.colors.primaryAccent4)
            
            expandableFees
        }
        .frame(maxHeight: showFees ? nil : 0)
        .clipped()
    }
    
    var expandableFees: some View {
        VStack(spacing: 16) {
            if swapViewModel.showFees(tx: tx) {
                swapFees
            }
            
            if swapViewModel.showGas(tx: tx) {
                swapGas
            }
        }
    }
    
    var swapFees: some View {
        getSummaryCell(
            leadingText: "swapFee",
            trailingText: swapViewModel.swapFeeString(tx: tx)
        )
    }
    
    var swapGas: some View {
        getSummaryCell(
            leadingText: "networkFee",
            trailingText: "\(swapViewModel.swapGasString(tx: tx))(\(swapViewModel.approveFeeString(tx: tx)))"
        )
    }
    
    private func getSummaryCell(leadingText: String, trailingText: String) -> some View {
        HStack {
            Text(NSLocalizedString(leadingText, comment: ""))
                .foregroundColor(Theme.colors.textTertiary)
            
            Spacer()
            
            Text(trailingText)
                .foregroundColor(Theme.colors.textSecondary)
                .redacted(reason: swapViewModel.isLoading ? .placeholder : [])
        }
        .font(Theme.fonts.caption12)
    }
    
    private func getImage(_ image: String) -> some View {
        Image(image)
            .resizable()
            .frame(width: 16, height: 16)
    }
    
    private func getErrorCell(text: String) -> some View {
        HStack() {
            Text(text)
                .foregroundColor(Theme.colors.alertError)
                .font(Theme.fonts.caption12)
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
