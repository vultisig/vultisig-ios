//
//  NativeSwapPoller.swift
//  VultisigApp
//
//  `DoneStatusPoller` driven by `NativeSwapTrackingService.shared`. Used by
//  native THORChain / MayaChain market swaps, where the source-chain RPC poller
//  confirms the DEPOSIT and so called a swap the protocol refunded successful.
//
//  Same shape as `LimitOrderPoller`: the row is recorded with its tracking
//  metadata inline (`SwapDoneScreen.recordTxHistory` /
//  `TransactionHistoryRecorder.recordFromKeysignPayload`), so all that's left
//  here is to hand the row to the tracker and translate what it publishes.
//

import Foundation
import SwiftUI

@MainActor
final class NativeSwapPoller: DoneStatusPoller {
    let initialStatus: TransactionStatus

    private let txHash: String
    private let pubKeyECDSA: String
    private let estimatedTime: String
    private let tracker: NativeSwapTrackingService

    private var observationTask: Task<Void, Never>?

    init(
        txHash: String,
        pubKeyECDSA: String,
        sourceChain: Chain,
        tracker: NativeSwapTrackingService? = nil
    ) {
        self.txHash = txHash
        self.pubKeyECDSA = pubKeyECDSA
        self.estimatedTime = ChainStatusConfig.config(for: sourceChain).estimatedTime
        self.tracker = tracker ?? .shared
        self.initialStatus = .broadcasted(estimatedTime: estimatedTime)
    }

    // MARK: - Lifecycle

    func start(onStatus: @escaping (TransactionStatus) -> Void) {
        guard observationTask == nil else { return }
        startTrackerIfQueued()

        observationTask = Task { [tracker, txHash, estimatedTime] in
            onStatus(Self.currentStatus(tracker: tracker, txHash: txHash, estimatedTime: estimatedTime))
            for await _ in tracker.objectWillChange.values {
                // `objectWillChange` fires before the underlying map updates —
                // hop the main runloop so the read sees the post-publish value.
                await MainActor.run {
                    onStatus(Self.currentStatus(tracker: tracker, txHash: txHash, estimatedTime: estimatedTime))
                }
            }
        }
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil
    }

    private func startTrackerIfQueued() {
        let inFlight = (try? TransactionHistoryStorage.shared.fetchInFlightSwapTracking(
            providerKind: NativeSwapTrackingService.providerKind
        )) ?? []
        if let row = inFlight.first(where: { $0.txHash == txHash && $0.pubKeyECDSA == pubKeyECDSA }) {
            tracker.start(tx: row)
        }
    }

    private static func currentStatus(
        tracker: NativeSwapTrackingService,
        txHash: String,
        estimatedTime: String
    ) -> TransactionStatus {
        mapNativeSwapStatus(
            tracker.uiStatusByTxHash[txHash],
            failureReason: tracker.failureReasonByTxHash[txHash],
            estimatedTime: estimatedTime
        )
    }

    // MARK: - Pure mapper

    /// Pure mapping from the tracker's UI status to the done screen's
    /// `TransactionStatus`.
    ///
    /// - `nil` is the frame before the tracker has seen the row.
    /// - Everything in flight — the source still confirming, the swap
    ///   streaming, the payout not yet sent — is `.pending`. The deposit
    ///   confirming is NOT success: only the payout is.
    /// - A refund is a failure the user can act on; the reason says the funds
    ///   came back. A failure carries the chain's own reason when there is one.
    nonisolated static func mapNativeSwapStatus(
        _ ui: SwapTrackingUiStatus?,
        failureReason: String?,
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
            return .failed(reason: failureReason?.trimmedNonEmpty ?? "transactionFailedDescription".localized)
        case .resting, .expired, .cancelled, .cancelling:
            // Limit-order states, unreachable for a market swap. Enumerated so a
            // new status fails this switch to compile; `.pending` claims
            // neither outcome if one ever arrived.
            return .pending
        }
    }
}
