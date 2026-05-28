//
//  SwapDoneScreen.swift
//  VultisigApp
//
//  Swap-flow entry point onto the unified `DoneScreen`. Composes:
//  - default token slot (the swap from-coin hero — same hero as Send)
//  - custom detail slot: `SwapDoneSummaryCard` (from/to cards +
//    expandable fees + tx hash + approve hash)
//  - custom bottom-bar: "Track" + "Done" when a progress link exists
//
//  Status comes from `SwapKitStatusSource` for SwapKit-routed swaps
//  (so the cross-chain `/track` drives the header instead of the
//  source-chain RPC poller, which would surface a premature
//  "successful" once the source tx confirms) and
//  `ChainPollerStatusSource` for THORChain/Maya/1inch/Kyber/LiFi.
//
//  Audit (Mediator.shared.stop): the pre-refactor screen kicked off a
//  5-second-delayed `Mediator.shared.stop()` here. Confirmed redundant
//  — `SwapKeysignScreen.onDisappear` calls `viewModel.stopMediator()`
//  before this screen ever appears (verified at
//  Features/Swap/Views/Screens/SwapKeysignScreen.swift:64). Removed.
//

import SwiftUI

struct SwapDoneScreen: View {
    let vault: Vault
    let hash: String
    let approveHash: String?
    let chain: Chain
    let transaction: SwapTransaction
    let progressLink: String?

    @StateObject private var sendSummaryViewModel = SendSummaryViewModel()

    @Environment(\.openURL) var openURL
    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        DoneScreen(
            input: payload,
            statusService: DoneStatusServiceFactory.swap(
                txHash: hash,
                transaction: transaction,
                vault: vault
            ),
            tokenContent: {
                SwapDoneSummaryCard.initiator(
                    transaction: transaction,
                    vault: vault,
                    sendSummaryViewModel: sendSummaryViewModel,
                    hash: hash,
                    approveHash: approveHash
                )
            },
            detailContent: {
                // Swap intentionally swaps the secondary disclosure
                // out — the from/to/fees card above already covers
                // the detail surface.
                EmptyView()
            },
            bottomBarContent: {
                HStack(spacing: 8) {
                    if let link = progressLink, !link.isEmpty {
                        PrimaryButton(title: "track", type: .secondary) {
                            if let url = URL(string: link) {
                                openURL(url)
                            }
                        }
                    }
                    PrimaryButton(title: "done") {
                        appViewModel.restart()
                    }
                }
            }
        )
        .onAppear {
            recordTxHistory()
        }
    }

    private var payload: TransactionDonePayload {
        TransactionDonePayload(
            coin: transaction.fromCoin,
            amountCrypto: "\(transaction.fromAmount) \(transaction.fromCoin.ticker)",
            amountFiat: transaction.fromFiatAmount,
            hash: hash,
            explorerLink: ExplorerLinkBuilder.getExplorerURL(chain: chain, txid: hash),
            memo: "",
            isSend: false,
            fromAddress: transaction.fromCoin.address,
            toAddress: transaction.toCoin.address,
            fee: FeeDisplay(crypto: transaction.totalFeeString, fiat: ""),
            keysignPayload: nil,
            pubKeyECDSA: vault.pubKeyECDSA
        )
    }

    private func recordTxHistory() {
        if let approveHash {
            TransactionHistoryRecorder.shared.recordApprove(
                txHash: approveHash,
                pubKeyECDSA: vault.pubKeyECDSA,
                coin: transaction.fromCoin,
                amountCrypto: sendSummaryViewModel.getFromAmount(transaction),
                spender: transaction.router ?? "",
                chain: transaction.fromCoin.chain,
                explorerLink: ExplorerLinkBuilder.getExplorerURL(chain: transaction.fromCoin.chain, txid: approveHash)
            )
        }
        TransactionHistoryRecorder.shared.recordSwap(
            txHash: hash,
            approveTxHash: approveHash,
            pubKeyECDSA: vault.pubKeyECDSA,
            fromCoin: transaction.fromCoin,
            toCoin: transaction.toCoin,
            fromAmountCrypto: sendSummaryViewModel.getFromAmount(transaction),
            fromAmountFiat: transaction.fromFiatAmount,
            toAmountCrypto: sendSummaryViewModel.getToAmount(transaction),
            toAmountFiat: transaction.toFiatAmount,
            fromAddress: transaction.fromCoin.address,
            toAddress: transaction.toCoin.address,
            feeCrypto: transaction.totalFeeString,
            feeFiat: "",
            chain: transaction.fromCoin.chain,
            explorerLink: ExplorerLinkBuilder.getExplorerURL(chain: transaction.fromCoin.chain, txid: hash),
            provider: transaction.quote.displayName
        )
    }
}
