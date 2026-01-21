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
    let vault: Vault
    let hash: String
    let approveHash: String?
    let sendSummaryViewModel: SendSummaryViewModel
    let swapSummaryViewModel: SwapCryptoViewModel

    @EnvironmentObject var settingsViewModel: SettingsViewModel

    var body: some View {
        Group {
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

            if !tx.fromAddress.isEmpty {
                Separator()
                getGeneralCell(
                    title: "from",
                    description: tx.fromAddress,
                    isVerticalStacked: true
                )
            }

            if !tx.toAddress.isEmpty {
                Separator()
                getGeneralCell(
                    title: "to",
                    description: tx.toAddress,
                    isVerticalStacked: true
                )
            }

            if !tx.memo.isEmpty {
                let decodedMemo = tx.memo.decodedExtensionMemo

                Separator()

                // Show decoded memo if available, otherwise show original memo
                if let decodedMemo = decodedMemo, !decodedMemo.isEmpty {
                    getGeneralCell(
                        title: "action",
                        description: decodedMemo,
                        isBold: true
                    )
                } else {
                    getGeneralCell(
                        title: "memo",
                        description: tx.memo,
                        isBold: false
                    )
                }
            }

            if !getSendAmount(for: tx).isEmpty {
                Separator()
                getGeneralCell(
                    title: "amount",
                    description: getSendAmount(for: tx)
                )
            }

            if !getSendFiatAmount(for: tx).isEmpty {
                Separator()
                getGeneralCell(
                    title: "value",
                    description: getSendFiatAmount(for: tx)
                )
            }

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
                description: sendSummaryViewModel.getFromAmount(
                    tx,
                    selectedCurrency: settingsViewModel.selectedCurrency
                )
            )

            Separator()
            getGeneralCell(
                title: "to",
                description: sendSummaryViewModel.getToAmount(
                    tx,
                    selectedCurrency: settingsViewModel.selectedCurrency
                )
            )

            if swapSummaryViewModel.showFees(tx: tx) {
                Separator()
                getGeneralCell(
                    title: "swapFee",
                    description: swapSummaryViewModel.swapFeeString(tx: tx)
                )
            }

            if swapSummaryViewModel.showGas(tx: tx) {
                Separator()
                getGeneralCell(
                    title: "networkFee",
                    description: "\(swapSummaryViewModel.swapGasString(tx: tx))(~\(swapSummaryViewModel.approveFeeString(tx: tx)))"
                )
            }

            if swapSummaryViewModel.showTotalFees(tx: tx) {
                Separator()
                getGeneralCell(
                    title: "totalFee",
                    description: "\(swapSummaryViewModel.totalFeeString(tx: tx))"
                )
            }
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
        .font(Theme.fonts.bodyMRegular)
        .foregroundColor(Theme.colors.textPrimary)
        .bold(isBold)
    }

    private func getSendAmount(for tx: SendTransaction) -> String {
        let amountDecimal = tx.amount.toDecimal()
        return amountDecimal.formatForDisplay() + " " + tx.coin.ticker
    }

    private func getSendFiatAmount(for tx: SendTransaction) -> String {
        tx.amountInFiat.formatToFiat()
    }
}

#Preview {
    ZStack {
        Background()
        SendCryptoDoneSummary(
            sendTransaction: nil,
            swapTransaction: SwapTransaction(),
            vault: Vault.example,
            hash: "bc1psrjtwm7682v6nhx2uwfgcfelrennd7pcvqq7v6w",
            approveHash: "123bc1psrjtwm7682v6nhx2uwfgcfelrennd7pcvqq7",
            sendSummaryViewModel: SendSummaryViewModel(),
            swapSummaryViewModel: SwapCryptoViewModel()
        )
    }
    .environmentObject(SettingsViewModel())
}
