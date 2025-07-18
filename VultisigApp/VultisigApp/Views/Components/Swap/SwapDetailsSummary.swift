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
            .font(.body12BrockmannMedium)
            .foregroundColor(.neutral0)
            .rotationEffect(Angle(degrees: showFees ? 0 : 180))
    }
    
    var otherFees: some View {
        HStack {
            Rectangle()
                .frame(width: 1)
                .foregroundColor(.persianBlue200)
            
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
            leadingText: "providersFee",
            trailingText: swapViewModel.providersFeeString(tx: tx)
        )
    }
    
    var swapGas: some View {
        getSummaryCell(
            leadingText: "networkFee",
            trailingText: "\(swapViewModel.swapGasString(tx: tx))(\(swapViewModel.networkFeeString(tx: tx)))"
        )
    }
    
    func getProvider() -> String? {
        switch swapViewModel.keysignPayload?.swapPayload {
        case .oneInch:
            return "1Inch"
        case .kyberSwap:
            return "KyberSwap"
        case .thorchain:
            return "THORChain"
        case .mayachain:
            return "Maya Protocol"
        case .none:
            return nil
        }
    }
    
    private func getSummaryCell(leadingText: String, trailingText: String) -> some View {
        HStack {
            Text(NSLocalizedString(leadingText, comment: ""))
                .foregroundColor(.extraLightGray)
            
            Spacer()
            
            Text(trailingText)
                .foregroundColor(.lightText)
                .redacted(reason: swapViewModel.isLoading ? .placeholder : [])
        }
        .font(.body12BrockmannMedium)
    }
    
    private func getImage(_ image: String) -> some View {
        Image(image)
            .resizable()
            .frame(width: 16, height: 16)
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
