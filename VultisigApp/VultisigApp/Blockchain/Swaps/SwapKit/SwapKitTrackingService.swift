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

import Foundation
import OSLog

/// Storage surface the tracking service depends on. Extracted as a protocol
/// so unit tests can inject an in-memory fake without bringing up SwiftData.
@MainActor
protocol SwapKitTrackingStorage {
    func updateSwapKitStatus(
        txHash: String,
        pubKeyECDSA: String,
        latestStatus: String?,
        latestTrackingStatus: String?,
        uiStatus: SwapKitUiStatus,
        polledAt: Date
    ) throws
    func touchSwapKitLastPolled(
        txHash: String,
        pubKeyECDSA: String,
        polledAt: Date
    ) throws
    func fetchInFlightSwapKitSwaps() throws -> [TransactionHistoryData]
}

extension TransactionHistoryStorage: SwapKitTrackingStorage {}

@MainActor
final class SwapKitTrackingService {
    static let shared = SwapKitTrackingService(
        httpClient: HTTPClient(),
        storage: TransactionHistoryStorage.shared
    )

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
    private let storage: SwapKitTrackingStorage
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
        storage: SwapKitTrackingStorage,
        clock: @escaping () -> Date = Date.init
    ) {
        self.httpClient = httpClient
        self.storage = storage
        self.clock = clock
    }

    // MARK: - Public API

    /// Begin polling for `swap`. No-op if a poller is already running for the
    /// same `txHash`, the row isn't routed through SwapKit, or the row is
    /// already in a terminal state.
    func start(swap: TransactionHistoryData) {
        guard swap.isSwapKitRouted else {
            logger.debug("Skipping non-SwapKit row \(swap.txHash, privacy: .public)")
            return
        }
        guard !swap.swapKitUiStatus.isTerminal else {
            logger.debug("Skipping terminal SwapKit row \(swap.txHash, privacy: .public)")
            return
        }
        guard pollers[swap.txHash] == nil else {
            logger.debug("Poller already running for \(swap.txHash, privacy: .public)")
            return
        }
        guard isActive else {
            // App is backgrounded; register a placeholder so resume() picks
            // it up when ScenePhase flips back to .active.
            pollers[swap.txHash] = PollerEntry(swap: swap, task: nil, failingSince: nil, nextDelay: Self.baseInterval)
            return
        }
        let entry = PollerEntry(swap: swap, task: nil, failingSince: nil, nextDelay: Self.baseInterval)
        pollers[swap.txHash] = entry
        spawnTask(for: swap.txHash)
    }

    /// Stop the active poller (if any) and forget the entry. Used by the
    /// done-screen on disappear and the viewmodel on terminal-state.
    func stop(swap: TransactionHistoryData) {
        stop(txHash: swap.txHash)
    }

    func stop(txHash: String) {
        guard let entry = pollers.removeValue(forKey: txHash) else { return }
        entry.task?.cancel()
        logger.debug("Stopped poller for \(txHash, privacy: .public)")
    }

    /// One-shot refresh — fires a single `/track` request immediately
    /// regardless of the backoff schedule. Used by pull-to-refresh.
    func forceRefresh(swap: TransactionHistoryData) async {
        guard swap.isSwapKitRouted,
              let hash = swap.swapKitBroadcastHash,
              let chainId = swap.swapKitSourceChainId else { return }
        await pollOnce(txHash: swap.txHash, pubKeyECDSA: swap.pubKeyECDSA, broadcastHash: hash, chainId: chainId)
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

    /// On viewmodel `.onAppear` / `ScenePhase.active`, re-scan SwiftData for
    /// any non-terminal SwapKit rows the user has and start polling them.
    /// Idempotent — already-running pollers are left alone.
    func resumeInFlightSwaps() {
        let inFlight: [TransactionHistoryData]
        do {
            inFlight = try storage.fetchInFlightSwapKitSwaps()
        } catch {
            logger.error("Failed to fetch in-flight SwapKit swaps: \(error.localizedDescription, privacy: .public)")
            return
        }
        for swap in inFlight {
            start(swap: swap)
        }
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
        let swap = entry.swap
        guard let hash = swap.swapKitBroadcastHash,
              let chainId = swap.swapKitSourceChainId else {
            pollers.removeValue(forKey: txHash)
            return
        }
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.runLoop(
                txHash: txHash,
                pubKeyECDSA: swap.pubKeyECDSA,
                broadcastHash: hash,
                chainId: chainId
            )
        }
        pollers[txHash]?.task = task
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
            return handleSuccess(txHash: txHash, pubKeyECDSA: pubKeyECDSA, response: response.data)
        } catch {
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
           let started = pollers[txHash]?.swap.swapKitTrackingStartedAt ?? trackingStartedFromStorage(txHash: txHash, pubKeyECDSA: pubKeyECDSA),
           now.timeIntervalSince(started) > Self.unknownGiveUpInterval {
            uiStatus = .unknownPendingExtended
        }

        do {
            try storage.updateSwapKitStatus(
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

        // Reset backoff bookkeeping on every success — even mid-flight.
        if var entry = pollers[txHash] {
            let refreshedSwap = applyResponseToSwap(
                swap: entry.swap,
                response: response,
                now: now,
                uiStatus: uiStatus
            )
            entry.failingSince = nil
            entry.nextDelay = Self.baseInterval
            entry.swap = refreshedSwap
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
        try? storage.touchSwapKitLastPolled(txHash: txHash, pubKeyECDSA: pubKeyECDSA, polledAt: now)

        guard pollers[txHash] != nil else {
            return PollOutcome(shouldStop: true, nextDelay: 0)
        }

        let failingSince = pollers[txHash]?.failingSince ?? now
        pollers[txHash]?.failingSince = failingSince

        if now.timeIntervalSince(failingSince) > Self.failureGiveUpInterval {
            logger.warning("SwapKit /track unavailable for \(txHash, privacy: .public) — giving up after \(Int(Self.failureGiveUpInterval), privacy: .public)s")
            // Promote to a tracker-unavailable terminal so the UI can
            // surface "check explorer" copy without blocking the user.
            try? storage.updateSwapKitStatus(
                txHash: txHash,
                pubKeyECDSA: pubKeyECDSA,
                latestStatus: pollers[txHash]?.swap.swapKitLatestStatus,
                latestTrackingStatus: pollers[txHash]?.swap.swapKitLatestTrackingStatus,
                uiStatus: .unknownPendingExtended,
                polledAt: now
            )
            return PollOutcome(shouldStop: true, nextDelay: 0)
        }

        let current = pollers[txHash]?.nextDelay ?? Self.baseInterval
        let nextDelay = min(max(current * 2, Self.backoffInitial), Self.backoffCap)
        pollers[txHash]?.nextDelay = nextDelay

        logger.debug("SwapKit /track transient error for \(txHash, privacy: .public), backoff=\(Int(nextDelay), privacy: .public)s, error=\(error.localizedDescription, privacy: .public)")
        return PollOutcome(shouldStop: false, nextDelay: nextDelay)
    }

    private func applyResponseToSwap(
        swap: TransactionHistoryData,
        response: SwapKitTrackingResponse,
        now: Date,
        uiStatus: SwapKitUiStatus
    ) -> TransactionHistoryData {
        TransactionHistoryData(
            id: swap.id,
            txHash: swap.txHash,
            approveTxHash: swap.approveTxHash,
            pubKeyECDSA: swap.pubKeyECDSA,
            type: swap.type,
            status: swap.status,
            chainRawValue: swap.chainRawValue,
            coinTicker: swap.coinTicker,
            coinLogo: swap.coinLogo,
            coinChainLogo: swap.coinChainLogo,
            amountCrypto: swap.amountCrypto,
            amountFiat: swap.amountFiat,
            fromAddress: swap.fromAddress,
            toAddress: swap.toAddress,
            toCoinTicker: swap.toCoinTicker,
            toCoinLogo: swap.toCoinLogo,
            toCoinChainLogo: swap.toCoinChainLogo,
            toAmountCrypto: swap.toAmountCrypto,
            toAmountFiat: swap.toAmountFiat,
            swapProvider: swap.swapProvider,
            feeCrypto: swap.feeCrypto,
            feeFiat: swap.feeFiat,
            network: swap.network,
            explorerLink: swap.explorerLink,
            createdAt: swap.createdAt,
            completedAt: uiStatus.isTerminal ? now : swap.completedAt,
            estimatedTime: swap.estimatedTime,
            errorMessage: swap.errorMessage,
            swapKitSwapId: swap.swapKitSwapId,
            swapKitRouteId: swap.swapKitRouteId,
            swapKitBroadcastHash: swap.swapKitBroadcastHash,
            swapKitSourceChainId: swap.swapKitSourceChainId,
            swapKitProvider: swap.swapKitProvider,
            swapKitLatestStatus: response.status.rawValue,
            swapKitLatestTrackingStatus: response.trackingStatus,
            swapKitLastPolledAt: now,
            swapKitTrackingStartedAt: swap.swapKitTrackingStartedAt ?? now,
            // Mirror the storage rule: outage is set iff we just promoted
            // to `unknownPendingExtended`, cleared on every other UI status.
            swapKitTrackerOutage: uiStatus == .unknownPendingExtended
        )
    }

    private func trackingStartedFromStorage(txHash: String, pubKeyECDSA: String) -> Date? {
        // Best-effort lookup; if storage can't be read the give-up window is
        // simply skipped this round and re-evaluated next poll.
        let swaps = (try? storage.fetchInFlightSwapKitSwaps()) ?? []
        return swaps.first(where: { $0.txHash == txHash && $0.pubKeyECDSA == pubKeyECDSA })?.swapKitTrackingStartedAt
    }
}

// MARK: - Internal types

private struct PollerEntry {
    var swap: TransactionHistoryData
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
