//
//  SendCryptoDoneSummary.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-11-19.
//

import SwiftUI

struct SendCryptoDoneSummary: View {
    let sendTransaction: SendTransaction?
    let swapTransaction: SwapTransaction?
    
    let viewModel = SendSummaryViewModel()
    
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    var body: some View {
        ZStack {
            if let tx = sendTransaction {
                getSendCard(tx)
            } else if let tx = swapTransaction {
                getSwapCard(tx)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }
    
    private func getSendCard(_ tx: SendTransaction) -> some View {
        VStack(spacing: 18) {
            Separator()
            getGeneralCell(title: "from", description: tx.fromAddress, isVerticalStacked: true)
            Separator()
            getGeneralCell(title: "to", description: tx.toAddress, isVerticalStacked: true)
            Separator()
            getGeneralCell(title: "networkFee", description: tx.gasInReadable)
        }
    }
    
    private func getSwapCard(_ tx: SwapTransaction) -> some View {
        VStack(spacing: 18) {
            Separator()
            getGeneralCell(
                title: "from",
                description: viewModel.getFromAmount(
                    tx,
                    selectedCurrency: settingsViewModel.selectedCurrency
                )
            )
            
            Separator()
            getGeneralCell(
                title: "to",
                description: viewModel.getToAmount(
                    tx,
                    selectedCurrency: settingsViewModel.selectedCurrency
                )
            )
            
            Separator()
            getGeneralCell(
                title: "networkFee",
                description: viewModel.swapFeeString(tx)
            )
        }
    }
    
    private func getGeneralCell(title: String, description: String, isVerticalStacked: Bool = false) -> some View {
        ZStack {
            if isVerticalStacked {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString(title, comment: ""))
                    Text(description)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    Text(NSLocalizedString(title, comment: ""))
                    Spacer()
                    Text(description)
                }
            }
        }
        .font(.body16MenloBold)
        .foregroundColor(.neutral100)
    }
}

#Preview {
    SendCryptoDoneSummary(
        sendTransaction: SendTransaction(),
        swapTransaction: SwapTransaction()
    )
}
