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
//  closure the underlying tracker needs. The cosigner path closes the
//  pre-refactor gap where the peer device received no live status at
//  all on swap-finished.
//

import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "swapkit-poller")

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
                guard case let .swapkit(response, _, _) = transaction.quote else {
                    logger.warning("attach[initiator] skipped — transaction.quote is not .swapkit; txHash=\(txHash, privacy: .public)")
                    return
                }
                guard let chainId = SwapKitChainIdentifier.chainId(for: transaction.fromCoin.chain) else {
                    logger.warning("attach[initiator] skipped — no SwapKit chainId mapping for chain=\(transaction.fromCoin.chain.rawValue, privacy: .public); txHash=\(txHash, privacy: .public)")
                    return
                }
                logger.info("attach[initiator] txHash=\(txHash, privacy: .public) swapId=\(response.swapId, privacy: .public) routeId=\(response.routeId ?? "nil", privacy: .public) sourceChainId=\(chainId, privacy: .public) subProvider=\(response.subProvider, privacy: .public)")
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
                guard let chainId = SwapKitChainIdentifier.chainId(for: sourceChain) else {
                    logger.warning("attach[cosigner] skipped — no SwapKit chainId mapping for chain=\(sourceChain.rawValue, privacy: .public); txHash=\(txHash, privacy: .public)")
                    return
                }
                logger.info("attach[cosigner] txHash=\(txHash, privacy: .public) swapId=\(payload.swapID, privacy: .public) sourceChainId=\(chainId, privacy: .public) subProvider=\(payload.subProvider, privacy: .public)")
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
        logger.debug("startTrackerIfQueued: inFlight.count=\(inFlight.count) txHash=\(txHash, privacy: .public)")
        if let row = inFlight.first(where: { $0.txHash == txHash && $0.pubKeyECDSA == pubKeyECDSA }) {
            logger.info("startTrackerIfQueued: matched in-flight row, calling tracker.start; txHash=\(txHash, privacy: .public)")
            tracker.start(tx: row)
        } else {
            logger.warning("startTrackerIfQueued: NO in-flight row matched txHash=\(txHash, privacy: .public) — /track polling will not start; check that attachSwapTracking persisted the row")
        }
    }

    // MARK: - Lifecycle

    func start(onStatus: @escaping (TransactionStatus) -> Void) {
        guard observationTask == nil else {
            logger.debug("start() called while observationTask alive; no-op. txHash=\(self.txHash, privacy: .public)")
            return
        }
        logger.info("start() txHash=\(self.txHash, privacy: .public) estimatedTime=\(self.estimatedTime, privacy: .public)")
        attach()

        observationTask = Task { [tracker, txHash, estimatedTime] in
            // Seed from the current cache snapshot.
            let seedUi = tracker.uiStatusByTxHash[txHash]
            let seeded = Self.mapSwapKitStatus(seedUi, estimatedTime: estimatedTime)
            logger.debug("seed: ui=\(String(describing: seedUi), privacy: .public) → mapped=\(String(describing: seeded), privacy: .public)")
            onStatus(seeded)

            var emitCount = 0
            for await _ in tracker.objectWillChange.values {
                // `objectWillChange` fires before the underlying map
                // updates — hop the main runloop so the read sees the
                // post-publish value.
                emitCount += 1
                let count = emitCount
                await MainActor.run {
                    let ui = tracker.uiStatusByTxHash[txHash]
                    let mapped = Self.mapSwapKitStatus(ui, estimatedTime: estimatedTime)
                    logger.debug("emit #\(count) txHash=\(txHash, privacy: .public) ui=\(String(describing: ui), privacy: .public) → mapped=\(String(describing: mapped), privacy: .public)")
                    onStatus(mapped)
                }
            }
            logger.info("observation task ended (cancelled or stream closed) txHash=\(txHash, privacy: .public) emits=\(emitCount)")
        }
    }

    func stop() {
        logger.info("stop() txHash=\(self.txHash, privacy: .public)")
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
