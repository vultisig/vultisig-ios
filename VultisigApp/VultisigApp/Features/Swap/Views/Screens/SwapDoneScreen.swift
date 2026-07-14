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
//  Limit orders ride the same screen (`transaction.isLimit`): the
//  detail slot shows the "find your order in Transaction History"
//  banner and `onAppear` persists the `LimitOrderRecord` with the
//  broadcast hash spliced in.
//
//  Audit (Mediator.shared.stop): the pre-refactor screen kicked off a
//  5-second-delayed `Mediator.shared.stop()` here. Confirmed redundant
//  — the shared keysign screen's `onDisappear` calls `stopMediator()` for
//  the swap flow before this screen ever appears (`SigningKeysignScreen`).
//  Removed.
//

import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "swap-done-screen")

struct SwapDoneScreen: View {
    let vault: Vault
    let hash: String
    let approveHash: String?
    let chain: Chain
    let transaction: SwapTransaction
    let progressLink: String?

    @State private var didPersistLimitOrder = false

    private let limitStorage = LimitOrderStorageService()

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
                // the detail surface. Limit orders add the
                // "where to find your order" banner here.
                if transaction.isLimit {
                    limitOrdersInfoBanner
                } else {
                    EmptyView()
                }
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
            persistLimitOrderIfNeeded()
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
            // Limit orders carry no market quote, so the quote-driven
            // `totalFeeString` is empty; show the estimated source-chain network
            // fee (the only fee a resting `=<` order has) instead.
            fee: transaction.isLimit
                ? FeeDisplay(crypto: transaction.limitNetworkFeeString, fiat: transaction.limitNetworkFeeFiat)
                : FeeDisplay(crypto: transaction.totalFeeString, fiat: ""),
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
            // Limit orders carry no market quote — persist the estimated
            // source-chain network fee instead of the empty quote-driven total.
            feeCrypto: transaction.isLimit ? transaction.limitNetworkFeeString : transaction.totalFeeString,
            feeFiat: transaction.isLimit ? transaction.limitNetworkFeeFiat : "",
            chain: transaction.fromCoin.chain,
            explorerLink: ExplorerLinkBuilder.getExplorerURL(chain: transaction.fromCoin.chain, txid: hash),
            // Limit orders carry no market quote (`quote == nil`), so fall back to
            // the fixed provider — a placed `=<` order always routes through THORChain.
            provider: transaction.isLimit ? "THORChain" : (transaction.quote?.displayName ?? ""),
            // A resting limit order must not be arbitrated by the native
            // source-chain poller: that poller confirms the *inbound deposit*
            // and would flip the row to `.successful` within minutes, while the
            // order can rest unfilled for 12-72h. Tracking metadata is what
            // makes the registry resolve a service for this row, which is the
            // condition both `TransactionHistoryViewModel` and
            // `TransactionStatusPoller` gate native polling on.
            //
            // Passed inline (rather than a follow-up `attachSwapTracking`, the
            // SwapKit path) so the row can never exist untracked: everything
            // needed is known at record time.
            swapTracking: transaction.isLimit
                ? THORChainLimitTrackingService.metadata(
                    broadcastHash: hash,
                    sourceChain: transaction.fromCoin.chain
                )
                : nil
        )
    }

    /// Mirrors Figma 74765:106224 — info banner anchored above the bottom
    /// "Track / Done" actions on the limit-success state. Tells the user
    /// where to find their order in Transaction History.
    private var limitOrdersInfoBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.colors.textSecondary)
            VStack(alignment: .leading, spacing: 0) {
                Text("limitSwap.done.bannerTitle".localized)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textPrimary)
                Text("limitSwap.done.bannerDetail".localized)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Theme.colors.bgSurface1)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.colors.borderLight, lineWidth: 1)
        )
    }

    @MainActor
    private func persistLimitOrderIfNeeded() {
        guard !didPersistLimitOrder,
              let context = transaction.limitContext,
              !hash.isEmpty else { return }
        didPersistLimitOrder = true
        let record = context.with(inboundTxHash: hash)
        do {
            _ = try limitStorage.persist(record, for: vault)
        } catch {
            // Duplicate on retry is benign; everything else is logged but
            // doesn't surface — broadcast already succeeded.
            logger.warning("Failed to persist limit order: \(error.localizedDescription, privacy: .public)")
        }
    }
}
