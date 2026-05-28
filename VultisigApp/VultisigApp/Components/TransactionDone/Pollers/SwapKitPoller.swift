//
//  SwapKitPoller.swift
//  VultisigApp
//
//  `DoneStatusPoller` driven by `SwapKitTrackingService.shared`'s
//  `/track` poll. Used by SwapKit-routed swaps where the source-chain
//  RPC poller would surface a premature "successful" once the source
//  tx confirms (the cross-chain leg keeps running afterwards).
//
//  Two static factories — `initiator(...)` (full `SwapTransaction` in
//  hand) and `cosigner(...)` (only the SwapKit fields lifted off
//  `KeysignPayload.swapPayload(.swapkit)`) — both build the attach
//  closure the underlying tracker needs. The cosigner path is the gap
//  the previous `StaticStatusSource` left unfilled.
//

import Foundation
import SwiftUI

@MainActor
final class SwapKitPoller: DoneStatusPoller {
    let initialStatus: TransactionStatus

    private let txHash: String
    private let estimatedTime: String
    private let tracker: SwapKitTrackingService
    private let attach: @MainActor () -> Void

    private var observationTask: Task<Void, Never>?

    private init(
        txHash: String,
        sourceChain: Chain,
        tracker: SwapKitTrackingService,
        attach: @escaping @MainActor () -> Void
    ) {
        self.txHash = txHash
        self.estimatedTime = ChainStatusConfig.config(for: sourceChain).estimatedTime
        self.tracker = tracker
        self.attach = attach
        self.initialStatus = .broadcasted(estimatedTime: estimatedTime)
    }

    // MARK: - Factories

    /// Initiator-side construction: full `SwapTransaction` carries the
    /// SwapKit `swapId` / `routeId` / `subProvider` on its
    /// `.swapkit(response, _, _)` quote case.
    static func initiator(
        transaction: SwapTransaction,
        txHash: String,
        pubKeyECDSA: String,
        tracker: SwapKitTrackingService = .shared
    ) -> SwapKitPoller {
        SwapKitPoller(
            txHash: txHash,
            sourceChain: transaction.fromCoin.chain,
            tracker: tracker,
            attach: {
                guard case let .swapkit(response, _, _) = transaction.quote else { return }
                guard let chainId = SwapKitChainIdentifier.chainId(for: transaction.fromCoin.chain) else { return }
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
                Self.startTrackerIfQueued(tracker: tracker, txHash: txHash, pubKeyECDSA: pubKeyECDSA)
            }
        )
    }

    /// Cosigner-side construction: lifts the SwapKit fields off
    /// `KeysignPayload.swapPayload(.swapkit(SwapKitSwapPayload))`.
    /// `routeId` isn't on the proto-mappable payload — passing `nil`
    /// is allowed by `attachSwapTracking` (the doc note explicitly
    /// permits providers without a separate quote/build split).
    static func cosigner(
        payload: SwapKitSwapPayload,
        sourceChain: Chain,
        txHash: String,
        pubKeyECDSA: String,
        tracker: SwapKitTrackingService = .shared
    ) -> SwapKitPoller {
        SwapKitPoller(
            txHash: txHash,
            sourceChain: sourceChain,
            tracker: tracker,
            attach: {
                guard let chainId = SwapKitChainIdentifier.chainId(for: sourceChain) else { return }
                TransactionHistoryRecorder.shared.attachSwapTracking(
                    txHash: txHash,
                    pubKeyECDSA: pubKeyECDSA,
                    providerKind: SwapKitTrackingService.providerKind,
                    swapId: payload.swapID,
                    routeId: nil,
                    broadcastHash: txHash,
                    sourceChainId: chainId,
                    subProvider: payload.subProvider
                )
                Self.startTrackerIfQueued(tracker: tracker, txHash: txHash, pubKeyECDSA: pubKeyECDSA)
            }
        )
    }

    private static func startTrackerIfQueued(
        tracker: SwapKitTrackingService,
        txHash: String,
        pubKeyECDSA: String
    ) {
        let inFlight = (try? TransactionHistoryStorage.shared.fetchInFlightSwapTracking(
            providerKind: SwapKitTrackingService.providerKind
        )) ?? []
        if let row = inFlight.first(where: { $0.txHash == txHash && $0.pubKeyECDSA == pubKeyECDSA }) {
            tracker.start(tx: row)
        }
    }

    // MARK: - Lifecycle

    func start(onStatus: @escaping (TransactionStatus) -> Void) {
        guard observationTask == nil else { return }
        attach()

        observationTask = Task { [tracker, txHash, estimatedTime] in
            // Seed from the current cache snapshot.
            onStatus(Self.mapSwapKitStatus(tracker.uiStatusByTxHash[txHash], estimatedTime: estimatedTime))
            for await _ in tracker.objectWillChange.values {
                // `objectWillChange` fires before the underlying map
                // updates — hop the main runloop so the read sees the
                // post-publish value.
                await MainActor.run {
                    onStatus(Self.mapSwapKitStatus(tracker.uiStatusByTxHash[txHash], estimatedTime: estimatedTime))
                }
            }
        }
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil
    }

    // MARK: - Pure mapper

    /// Pure mapping from a SwapKit `/track` UI status to the done-screen's
    /// `TransactionStatus`. `static` + `nonisolated` so unit tests can
    /// pin the table without standing up a view.
    ///
    /// - `nil` is the pre-attach frame (the poller is constructed before
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
