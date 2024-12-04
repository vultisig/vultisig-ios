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
            getGeneralCell(
                title: "from",
                description: tx.fromAddress,
                isVerticalStacked: true
            )
            
            Separator()
            getGeneralCell(
                title: "to",
                description: tx.toAddress,
                isVerticalStacked: true
            )
            
            Separator()
            getGeneralCell(
                title: "memo",
                description: tx.memo.isEmpty ? "None" : tx.memo,
                isBold: false
            )
            
            Separator()
            getGeneralCell(
                title: "amount",
                description: getSendAmount(for: tx)
            )
            
            Separator()
            getGeneralCell(
                title: "value",
                description: getSendFiatAmount(for: tx)
            )
            
            Separator()
            getGeneralCell(
                title: "networkFee",
                description: tx.gasInReadable
            )
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
                title: "swapFee",
                description: viewModel.swapFeeString(tx)
            )
        }
    }
    
    private func getGeneralCell(title: String, description: String, isVerticalStacked: Bool = false, isBold: Bool = true) -> some View {
        ZStack {
            if isVerticalStacked {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString(title, comment: ""))
                        .bold()
                    
                    Text(description)
                        .opacity(isBold ? 1 : 0.4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    Text(NSLocalizedString(title, comment: ""))
                        .bold()
                    
                    Spacer()
                    
                    Text(description)
                        .opacity(isBold ? 1 : 0.4)
                }
            }
        }
        .font(.body16Menlo)
        .foregroundColor(.neutral100)
        .bold(isBold)
    }
    
    private func getSendAmount(for tx: SendTransaction) -> String {
        tx.amount.formatCurrencyWithSeparators(settingsViewModel.selectedCurrency) + " " + tx.coin.ticker
    }
    
    private func getSendFiatAmount(for tx: SendTransaction) -> String {
        tx.amountInFiat.formatToFiat().formatCurrencyWithSeparators(settingsViewModel.selectedCurrency)
    }
}

#Preview {
    ZStack {
        Background()
        SendCryptoDoneSummary(
            sendTransaction: SendTransaction(),
            swapTransaction: SwapTransaction()
        )
    }
    .environmentObject(SettingsViewModel())
}
