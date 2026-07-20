//
//  LimitOrderPoller.swift
//  VultisigApp
//
//  `DoneStatusPoller` driven by `THORChainLimitTrackingService.shared`'s
//  poll of the THORChain limit-swap queue. Used by THORChain limit (`=<`)
//  orders, which the source-chain RPC poller reports catastrophically
//  wrongly: it confirms the INBOUND DEPOSIT and so calls the order
//  "successful" seconds after it was placed, while the order may rest
//  unfilled for 12-72h.
//
//  Same shape as `SwapKitPoller` — and for the same reason. The tracking
//  service already owns the polling, the queue reconciliation and the
//  authoritative `LimitOrder` writes; this is only the adapter that turns
//  its published UI status into the done screen's `TransactionStatus`.
//
//  Unlike `SwapKitPoller` there is no `attach` step: a limit row is
//  recorded with its tracking metadata inline (`SwapDoneScreen`
//  `recordTxHistory` / `TransactionHistoryRecorder.recordFromKeysignPayload`),
//  precisely so the row can never exist untracked. All that's left here is
//  to hand the row to the tracker.
//

import Foundation
import SwiftUI

@MainActor
final class LimitOrderPoller: DoneStatusPoller {
    let initialStatus: TransactionStatus

    private let txHash: String
    private let pubKeyECDSA: String
    private let estimatedTime: String
    private let tracker: THORChainLimitTrackingService

    private var observationTask: Task<Void, Never>?

    init(
        txHash: String,
        pubKeyECDSA: String,
        sourceChain: Chain,
        tracker: THORChainLimitTrackingService = .shared
    ) {
        self.txHash = txHash
        self.pubKeyECDSA = pubKeyECDSA
        self.estimatedTime = ChainStatusConfig.config(for: sourceChain).estimatedTime
        self.tracker = tracker
        self.initialStatus = .broadcasted(estimatedTime: estimatedTime)
    }

    // MARK: - Lifecycle

    func start(onStatus: @escaping (TransactionStatus) -> Void) {
        guard observationTask == nil else { return }
        startTrackerIfQueued()

        observationTask = Task { [tracker, txHash, estimatedTime] in
            // Seed from the current cache snapshot.
            onStatus(Self.mapLimitStatus(tracker.uiStatusByTxHash[txHash], estimatedTime: estimatedTime))
            for await _ in tracker.objectWillChange.values {
                // `objectWillChange` fires before the underlying map updates —
                // hop the main runloop so the read sees the post-publish value.
                await MainActor.run {
                    onStatus(Self.mapLimitStatus(tracker.uiStatusByTxHash[txHash], estimatedTime: estimatedTime))
                }
            }
        }
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil
    }

    /// Hand the freshly-recorded row to the tracker. Reads it back from
    /// storage rather than synthesising one so the tracker starts from the
    /// same `TransactionHistoryData` the rest of the app sees — including the
    /// `fromAddress` the sender-scoped queue poll is keyed on, which a
    /// hand-built row could get subtly wrong.
    private func startTrackerIfQueued() {
        let inFlight = (try? TransactionHistoryStorage.shared.fetchInFlightSwapTracking(
            providerKind: THORChainLimitTrackingService.providerKind
        )) ?? []
        if let row = inFlight.first(where: { $0.txHash == txHash && $0.pubKeyECDSA == pubKeyECDSA }) {
            tracker.start(tx: row)
        }
    }

    // MARK: - Pure mapper

    /// Pure mapping from a limit-order tracking status to the done-screen's
    /// `TransactionStatus`. `static` + `nonisolated` so unit tests can pin the
    /// table without standing up a view.
    ///
    /// The copy these map onto lives on `TransactionActionVerb.limitOrder`,
    /// which re-casts the whole header vocabulary in terms of the ORDER.
    ///
    /// - `nil` is the pre-attach frame (the poller is constructed before
    ///   `start()` seeds the cache) — "Order submitted".
    /// - `.resting` is the whole point: the order is live in the queue and has
    ///   NOT filled. It maps to `.pending`, which the limit verb renders as
    ///   "Order placed / Resting until your price is met". It must never reach
    ///   `.confirmed`.
    /// - `.pending` / `.swapping` are the generic in-flight statuses a row can
    ///   carry before the first queue poll lands; same conservative answer.
    /// - `.unknownPendingExtended` is the tracker-outage sentinel. The limit
    ///   tracker never promotes to it (an outage must not hand authority back
    ///   to the deposit-confirming native poller), but a row could carry it
    ///   from another provider's write — stay pending rather than guess.
    /// - `.completed` is the only success: the order actually filled.
    /// - `.refunded` / `.expired` / `.cancelled` are terminal but NOT filled.
    ///   They map to `.failed` — not because an expiry is a bug, but because
    ///   the header has exactly one non-success terminal frame and reading
    ///   "successful" for an order that never filled is the failure mode this
    ///   whole poller exists to prevent. The reason line carries what actually
    ///   happened. This also matches how the tx-history row already collapses
    ///   these states (`TransactionHistoryStorage.updateSwapTrackingStatus`).
    nonisolated static func mapLimitStatus(
        _ ui: SwapTrackingUiStatus?,
        estimatedTime: String
    ) -> TransactionStatus {
        switch ui {
        case .none:
            return .broadcasted(estimatedTime: estimatedTime)
        case .resting, .pending, .swapping, .unknownPendingExtended:
            return .pending
        case .completed:
            return .confirmed
        case .refunded:
            return .failed(reason: "limitSwap.done.reason.refunded".localized)
        case .expired:
            return .failed(reason: "limitSwap.done.reason.expired".localized)
        case .cancelled:
            return .failed(reason: "limitSwap.done.reason.cancelled".localized)
        case .failed:
            return .failed(reason: "limitSwap.done.reason.failed".localized)
        }
    }
}
