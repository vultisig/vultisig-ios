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

    @State private var showAlert = false
    @StateObject private var sendSummaryViewModel = SendSummaryViewModel()
    @StateObject private var statusSourceBox: AnyTransactionDoneStatusSourceBox

    @Environment(\.openURL) var openURL
    @EnvironmentObject var appViewModel: AppViewModel

    init(
        vault: Vault,
        hash: String,
        approveHash: String?,
        chain: Chain,
        transaction: SwapTransaction,
        progressLink: String?
    ) {
        self.vault = vault
        self.hash = hash
        self.approveHash = approveHash
        self.chain = chain
        self.transaction = transaction
        self.progressLink = progressLink

        let source: any TransactionDoneStatusSource = Self.makeStatusSource(
            transaction: transaction,
            txHash: hash,
            vault: vault
        )
        _statusSourceBox = StateObject(wrappedValue: AnyTransactionDoneStatusSourceBox(source: source))
    }

    var body: some View {
        Screen {
            ZStack {
                Background()
                DoneScreen(
                    input: payload,
                    statusSource: statusSourceBox,
                    showAlert: $showAlert,
                    tokenContent: {
                        SwapDoneSummaryCard.initiator(
                            transaction: transaction,
                            vault: vault,
                            sendSummaryViewModel: sendSummaryViewModel,
                            hash: hash,
                            approveHash: approveHash,
                            showAlert: $showAlert
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
            }
            .overlay(PopupCapsule(text: "hashCopied", showPopup: $showAlert))
        }
        .screenTitle("done".localized)
        .screenBackButtonHidden()
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

    private static func makeStatusSource(
        transaction: SwapTransaction,
        txHash: String,
        vault: Vault
    ) -> any TransactionDoneStatusSource {
        if case .swapkit = transaction.quote {
            return SwapKitStatusSource(
                transaction: transaction,
                txHash: txHash,
                pubKeyECDSA: vault.pubKeyECDSA
            )
        }
        return ChainPollerStatusSource(
            txHash: txHash,
            chain: transaction.fromCoin.chain,
            coinTicker: transaction.fromCoin.ticker,
            amount: "\(transaction.fromAmount) \(transaction.fromCoin.ticker)",
            toAddress: transaction.toCoin.address,
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
