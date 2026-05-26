//
//  SwapKitStatusSource.swift
//  VultisigApp
//
//  `TransactionDoneStatusSource` adapter for SwapKit-routed swaps. Drives
//  status off `SwapKitTrackingService.shared`'s `/track` poll instead of
//  the native per-chain RPC poller — the latter would race against the
//  cross-chain leg and surface a premature "successful" once the source
//  tx confirms.
//
//  Lifted from `SwapCryptoDoneView` so the polling glue + `mapSwapKitStatus`
//  table live behind the unified status-source seam; the done view doesn't
//  need to know whether status came from a chain RPC or `/track`.
//

import Foundation
import SwiftUI

@MainActor
final class SwapKitStatusSource: TransactionDoneStatusSource {
    @Published private(set) var status: TransactionStatus

    private let transaction: SwapTransaction
    private let txHash: String
    private let pubKeyECDSA: String
    private let estimatedTime: String
    private let tracker: SwapKitTrackingService
    private var observationTask: Task<Void, Never>?

    init(
        transaction: SwapTransaction,
        txHash: String,
        pubKeyECDSA: String,
        tracker: SwapKitTrackingService? = nil
    ) {
        self.transaction = transaction
        self.txHash = txHash
        self.pubKeyECDSA = pubKeyECDSA
        self.estimatedTime = ChainStatusConfig.config(for: transaction.fromCoin.chain).estimatedTime
        self.tracker = tracker ?? SwapKitTrackingService.shared
        self.status = .broadcasted(estimatedTime: estimatedTime)
    }

    func start() {
        guard observationTask == nil else { return }

        attachSwapKitTrackingIfNeeded()

        observationTask = Task { [weak self] in
            guard let self else { return }
            // Seed once from the current cache snapshot, then react to
            // every subsequent publish from `SwapKitTrackingService`.
            self.refreshStatus()
            for await _ in self.tracker.objectWillChange.values {
                // `objectWillChange` fires before the underlying map updates,
                // so hop the main runloop to read the post-publish value.
                await MainActor.run { self.refreshStatus() }
            }
        }
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil
    }

    /// Wires SwapKit-routed swaps into the `/track` polling service. No-op
    /// for THORChain/Maya/1inch/Kyber/LiFi routes — those run through the
    /// chain poller (constructed via `ChainPollerStatusSource`).
    private func attachSwapKitTrackingIfNeeded() {
        guard case let .swapkit(response, _, _) = transaction.quote else { return }
        guard let chainId = SwapKitChainIdentifier.chainId(for: transaction.fromCoin.chain) else {
            // No chainId mapping for the source chain — `/track` would 400.
            // Skip polling; the explorer link remains as the fallback.
            return
        }
        TransactionHistoryRecorder.shared.attachSwapTracking(
            txHash: txHash,
            pubKeyECDSA: pubKeyECDSA,
            providerKind: SwapKitTrackingService.providerKind,
            swapId: response.swapId,
            routeId: response.routeId,
            broadcastHash: txHash,
            sourceChainId: chainId,
            subProvider: response.subProvider
        )
        let inFlight = (try? TransactionHistoryStorage.shared.fetchInFlightSwapTracking(providerKind: SwapKitTrackingService.providerKind)) ?? []
        if let row = inFlight.first(where: { $0.txHash == txHash && $0.pubKeyECDSA == pubKeyECDSA }) {
            tracker.start(tx: row)
        }
    }

    private func refreshStatus() {
        let ui = tracker.uiStatusByTxHash[txHash]
        status = SwapKitStatusSource.mapSwapKitStatus(ui, estimatedTime: estimatedTime)
    }

    /// Pure mapping from a SwapKit `/track` UI status to the done-screen's
    /// `TransactionStatus`. Extracted to a `static` so unit tests can pin
    /// the table without standing up a view.
    ///
    /// - `nil` is the pre-attach frame (the source is constructed before
    ///   `start()` wires up `/track` and seeds the cache) — show the
    ///   "Broadcasted" copy with the chain's estimated time, same as a
    ///   freshly-broadcast non-SwapKit swap.
    /// - `.pending` is the source-chain phase (`/track` reports
    ///   `not_started/starting/broadcasted/mempool/inbound`) — show the
    ///   "Pending" copy so users see real progress beyond "Broadcasted"
    ///   while the source-chain RPC catches up.
    /// - `.swapping` is the cross-chain leg (`/track` reports
    ///   `outbound/swapping`) — also show "Pending" until the destination
    ///   tx lands.
    /// - `.unknownPendingExtended` is the tracker-outage sentinel — keep
    ///   "Pending" rather than flipping to a terminal failure frame; the
    ///   user can still hit the SwapKit-tracker deep link for the truth.
    nonisolated static func mapSwapKitStatus(
        _ ui: SwapTrackingUiStatus?,
        estimatedTime: String
    ) -> TransactionStatus {
        switch ui {
        case .none:
            return .broadcasted(estimatedTime: estimatedTime)
        case .pending, .swapping, .unknownPendingExtended:
            return .pending
        case .completed:
            return .confirmed
        case .refunded:
            return .failed(reason: "swapKitStatusRefundedReason".localized)
        case .failed:
            return .failed(reason: "swapKitStatusFailedReason".localized)
        }
    }
}
