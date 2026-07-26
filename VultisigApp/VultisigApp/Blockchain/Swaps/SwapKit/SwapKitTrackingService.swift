//
//  SwapKitTrackingService.swift
//  VultisigApp
//
//  Owns the per-swap `POST /track` polling lifecycle for SwapKit-routed
//  swaps. One `Task` per active broadcast hash. Sleeps 10s between polls on
//  the happy path; exponential backoff (5min cap) on transient errors;
//  terminal status or 30 min of unbroken failures stops the task for good.
//
//  ScenePhase awareness lives here, not in the views: a single `setActive`
//  toggle pauses every running poller while the app is backgrounded and
//  resumes them when it returns to foreground. iOS background-execution
//  limits make reliable polling impossible while suspended anyway.
//
//  Inject `HTTPClientProtocol` + a clock via the initializer so unit tests can
//  drive the state machine through the documented sequence without ever
//  hitting the wire.
//
//  Conforms to `SwapTrackingService`. Discriminated by the `"swapKit"`
//  `providerKind` value stored on `SwapTrackingMetadata`.
//

import Foundation
import OSLog

/// Storage surface the tracking service depends on. Extracted as a protocol
/// so unit tests can inject an in-memory fake without bringing up SwiftData.
@MainActor
protocol SwapTrackingStorage {
    func updateSwapTrackingStatus(
        txHash: String,
        pubKeyECDSA: String,
        latestStatus: String?,
        latestTrackingStatus: String?,
        uiStatus: SwapTrackingUiStatus,
        polledAt: Date
    ) throws
    func touchSwapTrackingLastPolled(
        txHash: String,
        pubKeyECDSA: String,
        polledAt: Date
    ) throws
    func fetchInFlightSwapTracking(providerKind: String) throws -> [TransactionHistoryData]
}

extension TransactionHistoryStorage: SwapTrackingStorage {}

@MainActor
final class SwapKitTrackingService: ObservableObject, SwapTrackingService {
    // `providerKind` is read from non-isolated contexts (e.g. the
    // `TransactionHistoryData.swapKitTrackerURL` value-type extension), so
    // it can't inherit the class's MainActor isolation. The string is a
    // compile-time constant — there's no shared state to protect.
    nonisolated static let providerKind: String = "swapKit"

    static let shared = SwapKitTrackingService(
        httpClient: HTTPClient(),
        storage: TransactionHistoryStorage.shared
    )

    /// Latest UI status per `txHash`, observable by views that want to react
    /// to `/track` updates without re-reading SwiftData. Updated on every
    /// successful poll and on the give-up `unknownPendingExtended` promotion.
    @Published private(set) var uiStatusByTxHash: [String: SwapTrackingUiStatus] = [:]

    /// Polling cadence on the happy path. Conservative pick per
    /// `track-in-tx-history-plan.md` §"Polling cadence".
    private static let baseInterval: TimeInterval = 10
    /// Initial backoff applied after the first transient failure.
    private static let backoffInitial: TimeInterval = 15
    /// Backoff cap — never sleep longer than this between polls.
    private static let backoffCap: TimeInterval = 5 * 60
    /// After this much elapsed failure, give up and treat the swap as
    /// `failed` so the user isn't left looking at a forever-spinning row.
    private static let failureGiveUpInterval: TimeInterval = 30 * 60
    /// Auto-promote `unknown` to `failed` once it has persisted this long.
    private static let unknownGiveUpInterval: TimeInterval = 10 * 60

    private let httpClient: HTTPClientProtocol
    private let storage: SwapTrackingStorage
    private let clock: () -> Date
    private let logger = Logger(subsystem: "com.vultisig.app", category: "swapkit-tracking")

    /// Active poller registry keyed by `txHash` (the local broadcast hash
    /// the row was originally recorded under — not the SwapKit broadcast
    /// hash, which is what the API call uses). Using `txHash` keeps the
    /// indexing aligned with the existing on-chain status poller.
    private var pollers: [String: PollerEntry] = [:]
    private var isActive: Bool = true

    init(
        httpClient: HTTPClientProtocol,
        storage: SwapTrackingStorage,
        clock: @escaping () -> Date = Date.init
    ) {
        self.httpClient = httpClient
        self.storage = storage
        self.clock = clock
    }

    // MARK: - SwapTrackingService

    /// Begin polling for `tx`. No-op if a poller is already running for the
    /// same `txHash`, the row isn't owned by this provider, or the row is
    /// already in a terminal state.
    func start(tx: TransactionHistoryData) {
        guard isOwnedByThisProvider(tx) else {
            logger.debug("Skipping non-SwapKit row \(tx.txHash, privacy: .public)")
            return
        }
        // Seed the observable cache with whatever status was last persisted so
        // views that mount before the first poll completes still see the right
        // state (e.g. after app relaunch on a still-in-flight swap).
        uiStatusByTxHash[tx.txHash] = tx.swapTrackingUiStatus
        guard !tx.swapTrackingUiStatus.isTerminal else {
            logger.debug("Skipping terminal SwapKit row \(tx.txHash, privacy: .public)")
            return
        }
        guard pollers[tx.txHash] == nil else {
            logger.debug("Poller already running for \(tx.txHash, privacy: .public)")
            return
        }
        guard isActive else {
            // App is backgrounded; register a placeholder so resume() picks
            // it up when ScenePhase flips back to .active.
            pollers[tx.txHash] = PollerEntry(tx: tx, task: nil, failingSince: nil, nextDelay: Self.baseInterval)
            return
        }
        let entry = PollerEntry(tx: tx, task: nil, failingSince: nil, nextDelay: Self.baseInterval)
        pollers[tx.txHash] = entry
        spawnTask(for: tx.txHash)
    }

    func stop(txHash: String) {
        guard let entry = pollers.removeValue(forKey: txHash) else { return }
        entry.task?.cancel()
        logger.debug("Stopped poller for \(txHash, privacy: .public)")
    }

    /// On viewmodel `.onAppear` / `ScenePhase.active`, re-scan SwiftData for
    /// any non-terminal SwapKit rows the user has and start polling them.
    /// Idempotent — already-running pollers are left alone.
    ///
    /// `async` is required by the `SwapTrackingService` protocol so future
    /// providers can await an asynchronous fetch; this concrete impl's
    /// fetch happens synchronously through `TransactionHistoryStorage`.
    func resumeInFlight() async { // swiftlint:disable:this async_without_await
        let inFlight: [TransactionHistoryData]
        do {
            inFlight = try storage.fetchInFlightSwapTracking(providerKind: Self.providerKind)
        } catch {
            logger.error("Failed to fetch in-flight SwapKit swaps: \(error.localizedDescription, privacy: .public)")
            return
        }
        for tx in inFlight {
            start(tx: tx)
        }
    }

    /// Wired from the top-level ScenePhase observer. `false` cancels every
    /// running poller (preserving the registry for resume); `true` restarts
    /// pollers for every still-tracked row.
    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        if active {
            resumeAll()
        } else {
            suspendAll()
        }
    }

    /// Cancel every running poller and drop the whole registry. A hard
    /// teardown for the global reset: unlike `suspendAll()` (which keeps the
    /// registry so foreground can resume), nothing survives, so a later
    /// `resumeInFlight` starts only from what SwiftData still holds — which,
    /// after a reset, is nothing.
    func stopAllTracking() {
        for (_, entry) in pollers {
            entry.task?.cancel()
        }
        pollers.removeAll()
        uiStatusByTxHash.removeAll()
        logger.info("Stopped all SwapKit pollers (reset)")
    }

    // MARK: - Public helpers (SwapKit-specific)

    /// One-shot refresh — fires a single `/track` request immediately
    /// regardless of the backoff schedule. Used by pull-to-refresh.
    func forceRefresh(tx: TransactionHistoryData) async {
        guard isOwnedByThisProvider(tx),
              let tracking = tx.swapTracking,
              let hash = tracking.broadcastHash,
              let chainId = tracking.sourceChainId else { return }
        await pollOnce(txHash: tx.txHash, pubKeyECDSA: tx.pubKeyECDSA, broadcastHash: hash, chainId: chainId)
    }

    /// Test-only state inspection. Returns the number of currently-tracked
    /// `txHash`es so unit tests can assert lifecycle invariants.
    var trackedSwapCountForTesting: Int {
        pollers.count
    }

    // MARK: - Lifecycle helpers

    private func suspendAll() {
        for (_, entry) in pollers {
            entry.task?.cancel()
        }
        // Keep the registry — `resumeAll()` walks it to restart.
        pollers = pollers.mapValues { entry in
            var copy = entry
            copy.task = nil
            return copy
        }
        logger.info("Suspended SwapKit pollers (background)")
    }

    private func resumeAll() {
        for txHash in pollers.keys {
            spawnTask(for: txHash)
        }
        logger.info("Resumed SwapKit pollers (foreground): \(self.pollers.count, privacy: .public)")
    }

    private func spawnTask(for txHash: String) {
        guard let entry = pollers[txHash], entry.task == nil else { return }
        let tx = entry.tx
        guard let tracking = tx.swapTracking,
              let hash = tracking.broadcastHash,
              let chainId = tracking.sourceChainId else {
            pollers.removeValue(forKey: txHash)
            return
        }
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.runLoop(
                txHash: txHash,
                pubKeyECDSA: tx.pubKeyECDSA,
                broadcastHash: hash,
                chainId: chainId
            )
        }
        pollers[txHash]?.task = task
    }

    private func isOwnedByThisProvider(_ tx: TransactionHistoryData) -> Bool {
        tx.swapTracking?.providerKind == Self.providerKind
    }

    // MARK: - Loop

    private func runLoop(
        txHash: String,
        pubKeyECDSA: String,
        broadcastHash: String,
        chainId: String
    ) async {
        while !Task.isCancelled {
            let outcome = await pollOnce(
                txHash: txHash,
                pubKeyECDSA: pubKeyECDSA,
                broadcastHash: broadcastHash,
                chainId: chainId
            )
            if outcome.shouldStop {
                pollers.removeValue(forKey: txHash)
                return
            }
            let delay = outcome.nextDelay
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
        }
    }

    @discardableResult
    private func pollOnce(
        txHash: String,
        pubKeyECDSA: String,
        broadcastHash: String,
        chainId: String
    ) async -> PollOutcome {
        let request = SwapKitTrackRequest(hash: broadcastHash, chainId: chainId)
        do {
            let response = try await httpClient.request(
                SwapKitAPI.track(request),
                responseType: SwapKitTrackingResponse.self
            )
            // `stopAllTracking()` (the global reset) cancels this task while the
            // request is in flight. A late response must not write status or the
            // observable cache back for a row that is being deleted. `handleFailure`
            // already guards on the poller registry; success needs an explicit
            // check because `forceRefresh` legitimately calls `pollOnce` without a
            // registered poller.
            if Task.isCancelled { return PollOutcome(shouldStop: true, nextDelay: 0) }
            return handleSuccess(txHash: txHash, pubKeyECDSA: pubKeyECDSA, response: response.data)
        } catch {
            if Task.isCancelled { return PollOutcome(shouldStop: true, nextDelay: 0) }
            return handleFailure(txHash: txHash, pubKeyECDSA: pubKeyECDSA, error: error)
        }
    }

    private func handleSuccess(
        txHash: String,
        pubKeyECDSA: String,
        response: SwapKitTrackingResponse
    ) -> PollOutcome {
        let now = clock()
        var uiStatus = SwapKitTrackingStatusMapper.map(response)

        // Promote `unknown` → `failed` after the give-up window so the row
        // doesn't hang forever when SwapKit can't index the hash.
        if uiStatus == .pending,
           response.trackingStatus?.lowercased() == "unknown" || response.status == .unknown,
           let started = pollers[txHash]?.tx.swapTracking?.trackingStartedAt ?? trackingStartedFromStorage(txHash: txHash, pubKeyECDSA: pubKeyECDSA),
           now.timeIntervalSince(started) > Self.unknownGiveUpInterval {
            uiStatus = .unknownPendingExtended
        }

        do {
            try storage.updateSwapTrackingStatus(
                txHash: txHash,
                pubKeyECDSA: pubKeyECDSA,
                latestStatus: response.status.rawValue,
                latestTrackingStatus: response.trackingStatus,
                uiStatus: uiStatus,
                polledAt: now
            )
        } catch {
            logger.error("Failed to persist SwapKit status for \(txHash, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        // Mirror the persisted status into the observable cache so any view
        // currently rendering this row updates without re-reading SwiftData.
        uiStatusByTxHash[txHash] = uiStatus

        // Reset backoff bookkeeping on every success — even mid-flight.
        if var entry = pollers[txHash] {
            let refreshedTx = applyResponseToTx(
                tx: entry.tx,
                response: response,
                now: now,
                uiStatus: uiStatus
            )
            entry.failingSince = nil
            entry.nextDelay = Self.baseInterval
            entry.tx = refreshedTx
            pollers[txHash] = entry
        }

        if uiStatus.isTerminal {
            return PollOutcome(shouldStop: true, nextDelay: 0)
        }
        return PollOutcome(shouldStop: false, nextDelay: Self.baseInterval)
    }

    private func handleFailure(
        txHash: String,
        pubKeyECDSA: String,
        error: Error
    ) -> PollOutcome {
        let now = clock()
        try? storage.touchSwapTrackingLastPolled(txHash: txHash, pubKeyECDSA: pubKeyECDSA, polledAt: now)

        guard pollers[txHash] != nil else {
            return PollOutcome(shouldStop: true, nextDelay: 0)
        }

        let failingSince = pollers[txHash]?.failingSince ?? now
        pollers[txHash]?.failingSince = failingSince

        if now.timeIntervalSince(failingSince) > Self.failureGiveUpInterval {
            logger.warning("SwapKit /track unavailable for \(txHash, privacy: .public) — giving up after \(Int(Self.failureGiveUpInterval), privacy: .public)s")
            // Promote to a tracker-unavailable terminal so the UI can
            // surface "check explorer" copy without blocking the user.
            try? storage.updateSwapTrackingStatus(
                txHash: txHash,
                pubKeyECDSA: pubKeyECDSA,
                latestStatus: pollers[txHash]?.tx.swapTracking?.latestStatus,
                latestTrackingStatus: pollers[txHash]?.tx.swapTracking?.latestTrackingStatus,
                uiStatus: .unknownPendingExtended,
                polledAt: now
            )
            uiStatusByTxHash[txHash] = .unknownPendingExtended
            return PollOutcome(shouldStop: true, nextDelay: 0)
        }

        let current = pollers[txHash]?.nextDelay ?? Self.baseInterval
        let nextDelay = min(max(current * 2, Self.backoffInitial), Self.backoffCap)
        pollers[txHash]?.nextDelay = nextDelay

        logger.debug("SwapKit /track transient error for \(txHash, privacy: .public), backoff=\(Int(nextDelay), privacy: .public)s, error=\(error.localizedDescription, privacy: .public)")
        return PollOutcome(shouldStop: false, nextDelay: nextDelay)
    }

    private func applyResponseToTx(
        tx: TransactionHistoryData,
        response: SwapKitTrackingResponse,
        now: Date,
        uiStatus: SwapTrackingUiStatus
    ) -> TransactionHistoryData {
        let oldTracking = tx.swapTracking
        let refreshedTracking = SwapTrackingMetadataData(
            providerKind: oldTracking?.providerKind ?? Self.providerKind,
            swapId: oldTracking?.swapId,
            routeId: oldTracking?.routeId,
            broadcastHash: oldTracking?.broadcastHash,
            sourceChainId: oldTracking?.sourceChainId,
            subProvider: oldTracking?.subProvider,
            latestStatus: response.status.rawValue,
            latestTrackingStatus: response.trackingStatus,
            lastPolledAt: now,
            trackingStartedAt: oldTracking?.trackingStartedAt ?? now,
            // Mirror the storage rule: outage is set iff we just promoted
            // to `unknownPendingExtended`, cleared on every other UI status.
            trackerOutage: uiStatus == .unknownPendingExtended
        )
        return TransactionHistoryData(
            id: tx.id,
            txHash: tx.txHash,
            approveTxHash: tx.approveTxHash,
            pubKeyECDSA: tx.pubKeyECDSA,
            type: tx.type,
            status: tx.status,
            chainRawValue: tx.chainRawValue,
            coinTicker: tx.coinTicker,
            coinLogo: tx.coinLogo,
            coinChainLogo: tx.coinChainLogo,
            amountCrypto: tx.amountCrypto,
            amountFiat: tx.amountFiat,
            fromAddress: tx.fromAddress,
            toAddress: tx.toAddress,
            toCoinTicker: tx.toCoinTicker,
            toCoinLogo: tx.toCoinLogo,
            toCoinChainLogo: tx.toCoinChainLogo,
            toAmountCrypto: tx.toAmountCrypto,
            toAmountFiat: tx.toAmountFiat,
            swapProvider: tx.swapProvider,
            feeCrypto: tx.feeCrypto,
            feeFiat: tx.feeFiat,
            network: tx.network,
            explorerLink: tx.explorerLink,
            createdAt: tx.createdAt,
            completedAt: uiStatus.isTerminal ? now : tx.completedAt,
            estimatedTime: tx.estimatedTime,
            errorMessage: tx.errorMessage,
            swapTracking: refreshedTracking
        )
    }

    private func trackingStartedFromStorage(txHash: String, pubKeyECDSA: String) -> Date? {
        // Best-effort lookup; if storage can't be read the give-up window is
        // simply skipped this round and re-evaluated next poll.
        let swaps = (try? storage.fetchInFlightSwapTracking(providerKind: Self.providerKind)) ?? []
        return swaps.first(where: { $0.txHash == txHash && $0.pubKeyECDSA == pubKeyECDSA })?.swapTracking?.trackingStartedAt
    }
}

// MARK: - Internal types

private struct PollerEntry {
    var tx: TransactionHistoryData
    var task: Task<Void, Never>?
    /// Timestamp of the first failure in the current failure streak. `nil`
    /// when the last poll succeeded.
    var failingSince: Date?
    /// The delay (seconds) to apply before the next poll. Reset to
    /// `baseInterval` on success; doubled on failure up to `backoffCap`.
    var nextDelay: TimeInterval
}

private struct PollOutcome {
    let shouldStop: Bool
    let nextDelay: TimeInterval
}
