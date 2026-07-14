//
//  THORChainLimitTrackingService.swift
//  VultisigApp
//
//  Tracking provider for THORChain limit (`=<`) orders. Discriminated by the
//  `"thorchainLimit"` `providerKind` stored on `SwapTrackingMetadata`.
//
//  Why this exists at all, before it can poll anything:
//
//  A placed limit order is recorded as an ordinary swap row. The arbitration
//  gate (`TransactionHistoryViewModel` / `TransactionStatusPoller`) only skips
//  native source-chain polling when a tracking service resolves for the row.
//  With no service registered, the native `ChainPoller` confirms the *inbound
//  deposit* and flips the row to `.successful` within minutes — while the order
//  may rest unfilled for 12-72h. Registering this provider is what makes the
//  gate skip native polling, so a resting order stops being reported as done.
//
//  This stage deliberately reports no status of its own: with metadata attached
//  and no poll recorded, `swapTrackingUiStatus` maps to `.pending`, which is
//  non-terminal and honest — the order *is* pending. "Still resting" beats
//  "Successful" on an order that hasn't filled.
//
//  The list-poll state machine (`queue/limit_swaps?sender=`), the authoritative
//  `LimitOrder` status write, and the resting/partially-filled/expired UI states
//  land next; this type is the seam they attach to.
//

import Foundation
import OSLog

@MainActor
final class THORChainLimitTrackingService: ObservableObject, SwapTrackingService {
    // Read from non-isolated contexts (the registry dispatches on it without
    // an instance), so it can't inherit the class's MainActor isolation. A
    // compile-time constant — no shared state to protect.
    nonisolated static let providerKind: String = "thorchainLimit"

    static let shared = THORChainLimitTrackingService(
        storage: TransactionHistoryStorage.shared
    )

    /// Latest UI status per `txHash`, observable by views that want to react
    /// without re-reading SwiftData.
    @Published private(set) var uiStatusByTxHash: [String: SwapTrackingUiStatus] = [:]

    private let storage: SwapTrackingStorage
    private let logger = Logger(subsystem: "com.vultisig.app", category: "thorchain-limit-tracking")

    /// Rows this service has taken ownership of, keyed by `txHash`. No polling
    /// task hangs off them yet — the registry only needs `service(for:)` to
    /// resolve for the gate to hold.
    private var tracked: Set<String> = []
    private var isActive: Bool = true

    init(storage: SwapTrackingStorage) {
        self.storage = storage
    }

    // MARK: - SwapTrackingService

    /// Take ownership of `tx` and seed its observable status. No-op for rows
    /// owned by another provider or already terminal.
    func start(tx: TransactionHistoryData) {
        guard isOwnedByThisProvider(tx) else {
            logger.debug("Skipping non-limit row \(tx.txHash, privacy: .public)")
            return
        }
        // Seed from whatever was last persisted so a view mounting before the
        // first poll (e.g. after relaunch on a still-resting order) sees the
        // right state rather than a default.
        uiStatusByTxHash[tx.txHash] = tx.swapTrackingUiStatus
        guard !tx.swapTrackingUiStatus.isTerminal else {
            logger.debug("Skipping terminal limit row \(tx.txHash, privacy: .public)")
            return
        }
        tracked.insert(tx.txHash)
    }

    func stop(txHash: String) {
        tracked.remove(txHash)
    }

    /// Re-scan SwiftData for non-terminal limit rows and take ownership of
    /// them. Idempotent.
    ///
    /// `async` is required by the protocol so providers can await an
    /// asynchronous fetch; this fetch is synchronous through
    /// `TransactionHistoryStorage`.
    func resumeInFlight() async { // swiftlint:disable:this async_without_await
        let inFlight: [TransactionHistoryData]
        do {
            inFlight = try storage.fetchInFlightSwapTracking(providerKind: Self.providerKind)
        } catch {
            logger.error("Failed to fetch in-flight limit orders: \(error.localizedDescription, privacy: .public)")
            return
        }
        for tx in inFlight {
            start(tx: tx)
        }
    }

    /// Wired from the top-level ScenePhase observer. Nothing to suspend until
    /// the poll loop exists; the flag is kept so resume/suspend stays a no-op
    /// rather than an error, and so the loop inherits correct state.
    func setActive(_ active: Bool) {
        isActive = active
    }

    // MARK: - Test-only inspection

    /// Number of rows currently owned by this service.
    var trackedOrderCountForTesting: Int { tracked.count }

    /// Whether the service considers itself foreground-active.
    var isActiveForTesting: Bool { isActive }

    // MARK: - Helpers

    private func isOwnedByThisProvider(_ tx: TransactionHistoryData) -> Bool {
        tx.swapTracking?.providerKind == Self.providerKind
    }
}

extension THORChainLimitTrackingService {
    /// The tracking metadata a limit-order row must carry for the arbitration
    /// gate to hand this provider authority over it.
    ///
    /// One factory shared by the initiator and co-signer recording paths — the
    /// gate turns on `providerKind` alone, so a path that built the metadata
    /// slightly differently would still be gated, but would then be tracked
    /// with the wrong identifiers. A limit order is identified on-chain by its
    /// inbound tx hash; there is no aggregator-issued swap/route id to carry.
    nonisolated static func metadata(
        broadcastHash: String,
        sourceChain: Chain
    ) -> SwapTrackingMetadataData {
        SwapTrackingMetadataData(
            providerKind: providerKind,
            swapId: nil,
            routeId: nil,
            broadcastHash: broadcastHash,
            sourceChainId: sourceChain.rawValue,
            subProvider: nil
        )
    }
}
