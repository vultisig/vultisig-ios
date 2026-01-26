//
//  SendCryptoDoneContentView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/07/2025.
//

import SwiftUI
import RiveRuntime

struct SendCryptoDoneContentView: View {
    let input: SendCryptoContent
    @Binding var showAlert: Bool
    var onDone: () -> Void = {}

    @State var navigateToHome = false
    @StateObject private var statusViewModel: TransactionStatusViewModel

    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.router) var router

    init(input: SendCryptoContent, showAlert: Binding<Bool>, onDone: @escaping () -> Void = {}) {
        self.input = input
        self._showAlert = showAlert
        self.onDone = onDone

        // Initialize status view model with metadata
        _statusViewModel = StateObject(wrappedValue: TransactionStatusViewModel(
            txHash: input.hash,
            chain: input.coin.chain,
            coinTicker: input.coin.ticker,
            amount: input.amountCrypto,
            toAddress: input.toAddress
        ))
    }

    var body: some View {
        VStack {
            ScrollView {
                VStack(spacing: 8) {
                    // Status-aware header
                    SendCryptoDoneHeaderView(
                        coin: input.coin,
                        cryptoAmount: input.amountCrypto,
                        fiatAmount: input.amountFiat.formatToFiat(includeCurrencySymbol: true),
                        status: statusViewModel.status
                    )

                    VStack(spacing: 16) {
                        Group {
                            SendCryptoTransactionHashRowView(
                                hash: input.hash,
                                explorerLink: input.explorerLink,
                                showCopy: true,
                                showAlert: $showAlert
                            )
                            Separator()
                                .opacity(0.8)
                        }
                        .showIf(input.hash.isNotEmpty)

                        transactionDetailsButton
                    }
                    .font(Theme.fonts.bodySMedium)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .background(Theme.colors.bgSurface1)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Theme.colors.bgSurface2, lineWidth: 1)
                    )
                }
            }

            PrimaryButton(title: "done") {
                onDoneButtonPressed()
            }
        }
        .onChange(of: navigateToHome) { _, newValue in
            guard newValue else { return }
            appViewModel.restart()
        }
        .onAppear {
            // Start polling for transaction status
            statusViewModel.startPolling()
        }
        .onDisappear {
            // Stop polling when view disappears
            statusViewModel.stopPolling()
        }
    }

    private func onDoneButtonPressed() {
        onDone()
        navigateToHome = true
    }

    var transactionDetailsButton: some View {
        Button {
            router.navigate(to: SendRoute.transactionDetails(input: input))
        } label: {
            HStack {
                Text(NSLocalizedString("transactionDetails", comment: ""))
                Spacer()
                Image(systemName: "chevron.right")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SendCryptoDoneView(
        vault: .example,
        hash: "294FF0BCDDA7E79140782FB3F5F759FFEE1C11639194FF500BAB6D92012C615C",
        approveHash: "",
        chain: .thorChain,
        sendTransaction: nil,
        swapTransaction: nil,
        isSend: true
    )
    .environmentObject(AppViewModel())
}
