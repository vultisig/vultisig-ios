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
//  Status comes from `SwapKitPoller` for SwapKit-routed swaps (so the
//  cross-chain `/track` drives the header instead of the source-chain
//  RPC poller, which would surface a premature "successful" once the
//  source tx confirms) and `ChainPoller` for THORChain/Maya/1inch/
//  Kyber/LiFi — wired via `DoneStatusServiceFactory.swap`.
//
//  Audit (Mediator.shared.stop): the pre-refactor screen kicked off a
//  5-second-delayed `Mediator.shared.stop()` here. Confirmed redundant
//  — the shared keysign screen's `onDisappear` calls `stopMediator()` for
//  the swap flow before this screen ever appears (`SigningKeysignScreen`).
//  Removed.
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

        // Persist tx-history rows *before* the SwiftUI body's appear
        // chain fires. The inner `DoneScreen.onAppear` runs
        // `statusService.start()` → `SwapKitPoller.attach()` →
        // `attachSwapTracking()`, and the storage layer's
        // `attachSwapTracking` no-ops when the parent
        // `TransactionHistoryItem` doesn't yet exist. Running
        // `recordTxHistory` from `.onAppear` (outer) racks up after the
        // inner appear, so the attach call missed and the `/track`
        // poll never started. `storage.save` short-circuits on
        // `exists(txHash:pubKeyECDSA:)`, so repeated re-inits are safe.
        Self.recordTxHistory(
            hash: hash,
            approveHash: approveHash,
            transaction: transaction,
            vault: vault
        )
    }

    var body: some View {
        DoneScreen(
            input: payload,
            statusService: DoneStatusServiceFactory.swap(
                txHash: hash,
                transaction: transaction,
                vault: vault
            ),
            navigationTitle: "overview".localized,
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

    /// Called from `init` so the `TransactionHistoryItem` row exists by
    /// the time `DoneScreen.onAppear` triggers
    /// `SwapKitPoller.attach()` → `attachSwapTracking()`. `static` to
    /// avoid needing `self.sendSummaryViewModel` (which doesn't exist
    /// until SwiftUI sets up the `@StateObject`).
    private static func recordTxHistory(
        hash: String,
        approveHash: String?,
        transaction: SwapTransaction,
        vault: Vault
    ) {
        let fromAmount = "\(transaction.fromAmount.formatForDisplay()) \(transaction.fromCoin.ticker)"
        let toAmount = "\(transaction.toAmountDecimal.formatForDisplay()) \(transaction.toCoin.ticker)"

        if let approveHash {
            TransactionHistoryRecorder.shared.recordApprove(
                txHash: approveHash,
                pubKeyECDSA: vault.pubKeyECDSA,
                coin: transaction.fromCoin,
                amountCrypto: fromAmount,
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
            fromAmountCrypto: fromAmount,
            fromAmountFiat: transaction.fromFiatAmount,
            toAmountCrypto: toAmount,
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
