//
//  NativeSwapTrackingService.swift
//  VultisigApp
//
//  Tracking provider for native THORChain / MayaChain market swaps,
//  discriminated by the `"nativeSwap"` `providerKind`.
//
//  Why it exists: the source-chain poller confirms the DEPOSIT, and the
//  THORChain status provider reads a Midgard `refund` as `.confirmed` (it serves
//  every THORChain transaction, where a refund is not always a failure). So a
//  swap the protocol refunded was reported as successful. Owning the row stands
//  the native poller down; this service reports the outcome instead, in two
//  phases — the order Windows and the SDK use:
//
//  1. The SOURCE transaction, through the per-chain status provider. Once a row
//     is tracked nothing else watches the source chain, and Midgard never
//     indexes a deposit that reverted — without this phase that swap would stay
//     pending forever.
//  2. Midgard on the protocol network, which indexes the inbound by its hash
//     whatever the source chain.
//
//  An HTTP error or an indexer that has not caught up is never a verdict: the
//  row stays in flight until the chain says what happened.
//

import Foundation
import OSLog

@MainActor
final class NativeSwapTrackingService: ObservableObject, SwapTrackingService {
    nonisolated static let providerKind = "nativeSwap"
    nonisolated static let baseInterval: TimeInterval = 10
    private static let backoffInitial: TimeInterval = 15
    private static let backoffCap: TimeInterval = 5 * 60

    static let shared = NativeSwapTrackingService(
        httpClient: HTTPClient(),
        sourceStatus: TransactionStatusService.shared,
        storage: TransactionHistoryStorage.shared
    )

    @Published private(set) var uiStatusByTxHash: [String: SwapTrackingUiStatus] = [:]
    /// The chain's own account of a `failed` outcome, for the done screen. Set
    /// together with the `.failed` status it explains, so an observer of
    /// `uiStatusByTxHash` reads both.
    private(set) var failureReasonByTxHash: [String: String] = [:]

    private let httpClient: HTTPClientProtocol
    private let sourceStatus: TransactionStatusChecking
    private let storage: NativeSwapTrackingStorage
    private let clock: () -> Date
    private let logger = Log.swap.other
    private var isActive = true
    private var generation = UUID()
    private var pollers: [RecordKey: Poller] = [:]
    private var requests: [RecordKey: UUID] = [:]
    private var completedRecords: [RecordKey: UUID] = [:]
    private var confirmedSources: Set<RecordKey> = []

    init(
        httpClient: HTTPClientProtocol,
        sourceStatus: TransactionStatusChecking,
        storage: NativeSwapTrackingStorage,
        clock: @escaping () -> Date = Date.init
    ) {
        self.httpClient = httpClient
        self.sourceStatus = sourceStatus
        self.storage = storage
        self.clock = clock
    }

    // MARK: - SwapTrackingService

    func start(tx: TransactionHistoryData) {
        guard Self.network(for: tx) != nil, Chain(rawValue: tx.chainRawValue) != nil else { return }
        let key = RecordKey(tx)
        guard completedRecords[key] != tx.id else { return }
        // Seeded only when nothing fresher is cached: callers hand in whatever
        // snapshot they loaded, which can predate this service's last write.
        if uiStatusByTxHash[tx.txHash] == nil {
            uiStatusByTxHash[tx.txHash] = tx.swapTrackingUiStatus
        }
        guard !tx.swapTrackingUiStatus.isTerminal else {
            stop(key: key)
            completedRecords[key] = tx.id
            return
        }
        guard pollers[key] == nil else { return }
        pollers[key] = Poller(tx: tx)
        if isActive { spawn(key: key) }
    }

    func resumeInFlight() async { // swiftlint:disable:this async_without_await
        guard !Task.isCancelled else { return }
        let rows: [TransactionHistoryData]
        do {
            rows = try storage.fetchInFlightSwapTracking(providerKind: Self.providerKind)
        } catch {
            logger.error("[NATIVESWAP] Failed to fetch in-flight native swaps: \(error.localizedDescription, privacy: .public)")
            return
        }
        for tx in rows { start(tx: tx) }
    }

    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        generation = UUID()
        requests.removeAll()
        for key in Array(pollers.keys) {
            pollers[key]?.task?.cancel()
            pollers[key]?.task = nil
            pollers[key]?.token = UUID()
            if active { spawn(key: key) }
        }
    }

    func stopAllTracking() {
        generation = UUID()
        for entry in pollers.values { entry.task?.cancel() }
        pollers.removeAll()
        requests.removeAll()
        completedRecords.removeAll()
        confirmedSources.removeAll()
        uiStatusByTxHash.removeAll()
        failureReasonByTxHash.removeAll()
    }

    /// One observation outside the schedule. `shouldApply` is re-checked after
    /// every network round-trip, so a caller whose context went away while the
    /// request was in flight discards the answer instead of writing it.
    ///
    /// `backgroundObservation` keeps signature parity with the other
    /// `SwapTrackingService` providers the Live Activity background runner
    /// dispatches to (see `TransactionActivityBackgroundService`); this
    /// provider's poll/backoff behavior does not otherwise depend on it.
    func forceRefresh(
        tx: TransactionHistoryData,
        backgroundObservation: Bool = false,
        shouldApply: @escaping @MainActor () -> Bool = { true }
    ) async {
        _ = backgroundObservation
        await refresh(tx: tx, shouldApply: shouldApply)
    }

    var trackedSwapCountForTesting: Int { pollers.count }

    func refreshForTesting(tx: TransactionHistoryData) async -> RefreshResult {
        await refresh(tx: tx, shouldApply: { true })
    }

    func pollingTaskForTesting(tx: TransactionHistoryData) -> Task<Void, Never>? { pollers[RecordKey(tx)]?.task }

    // MARK: - Polling loop

    private func spawn(key: RecordKey) {
        guard let entry = pollers[key], entry.task == nil else { return }
        let token = entry.token
        pollers[key]?.task = Task { [weak self] in
            var delay: TimeInterval = 0
            // `self` is re-acquired per poll rather than held across the sleep.
            while !Task.isCancelled {
                guard let next = await self?.pollOnce(key: key, token: token, previousDelay: delay) else { return }
                delay = next
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }

    /// Runs one refresh and returns the delay before the next, or `nil` when this
    /// loop has been superseded or stopped.
    private func pollOnce(key: RecordKey, token: UUID, previousDelay: TimeInterval) async -> TimeInterval? {
        guard isActive, let entry = pollers[key], entry.token == token else { return nil }
        let result = await refresh(tx: entry.tx, shouldApply: { [weak self] in
            self?.isActive == true && self?.pollers[key]?.token == token
        })
        guard !Task.isCancelled, isActive, pollers[key]?.token == token else { return nil }
        switch result {
        case .unavailable:
            return min(max(previousDelay * 2, Self.backoffInitial), Self.backoffCap)
        case .answered, .discarded:
            return Self.pollInterval(sourceChain: Chain(rawValue: entry.tx.chainRawValue))
        }
    }

    private func stop(key: RecordKey) {
        pollers.removeValue(forKey: key)?.task?.cancel()
        requests.removeValue(forKey: key)
        confirmedSources.remove(key)
    }

    // MARK: - One observation

    @discardableResult
    private func refresh(
        tx: TransactionHistoryData,
        shouldApply: @escaping @MainActor () -> Bool
    ) async -> RefreshResult {
        let key = RecordKey(tx)
        guard !Task.isCancelled, shouldApply(), !tx.swapTrackingUiStatus.isTerminal,
              completedRecords[key] != tx.id,
              let network = Self.network(for: tx), let hash = tx.swapTracking?.broadcastHash,
              let sourceChain = Chain(rawValue: tx.chainRawValue) else { return .discarded }
        let request = UUID()
        let capturedGeneration = generation
        requests[key] = request
        // The requests may finish after cancellation, a reset, another refresh,
        // or a vault/history change. Re-read the row before writing anything.
        let isStillWanted: @MainActor () -> Bool = { [weak self] in
            guard let self else { return false }
            return !Task.isCancelled && self.generation == capturedGeneration
                && self.requests[key] == request && shouldApply()
        }
        let observation = await observe(
            tx: tx, key: key, hash: hash, sourceChain: sourceChain, network: network, isStillWanted: isStillWanted
        )
        guard isStillWanted() else { return .discarded }
        requests.removeValue(forKey: key)
        let rows: [TransactionHistoryData]
        do {
            rows = try storage.fetchInFlightSwapTracking(providerKind: Self.providerKind)
        } catch {
            logger.error("[NATIVESWAP] Failed to re-read \(tx.txHash, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .discarded
        }
        guard let row = rows.first(where: {
            $0.id == tx.id && RecordKey($0) == key && !$0.swapTrackingUiStatus.isTerminal
                && Self.network(for: $0) == network && $0.swapTracking?.broadcastHash == hash
        }) else {
            stop(key: key)
            return .discarded
        }
        if observation.sourceConfirmed { confirmedSources.insert(key) }
        guard let status = observation.status else {
            return observation.unavailable ? .unavailable : .answered
        }
        let uiStatus = SwapKitTrackingStatusMapper.map(trackingStatus: status)
        // An in-flight answer repeats every poll during a streaming swap; only a
        // change is worth a write.
        if row.swapTracking?.latestTrackingStatus != status {
            // Stored before the status that makes it visible, and the status
            // waits for it: a terminal status ends polling, so a reason not
            // stored by then never would be. A refund stores none: History
            // words it from the status, in the reader's locale.
            if uiStatus == .failed, let reason = observation.failureReason {
                do {
                    try storage.updateErrorMessage(txHash: tx.txHash, pubKeyECDSA: tx.pubKeyECDSA, errorMessage: reason)
                } catch {
                    logger.error("[NATIVESWAP] Failed to persist the failure reason for \(tx.txHash, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    return .answered
                }
            }
            do {
                try storage.updateSwapTrackingStatus(
                    txHash: tx.txHash, pubKeyECDSA: tx.pubKeyECDSA,
                    latestStatus: status, latestTrackingStatus: status, uiStatus: uiStatus, polledAt: clock()
                )
            } catch {
                logger.error("[NATIVESWAP] Failed to persist \(status, privacy: .public) for \(tx.txHash, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return .answered
            }
        }
        if uiStatus == .failed, let reason = observation.failureReason {
            failureReasonByTxHash[tx.txHash] = reason
        }
        if uiStatusByTxHash[tx.txHash] != uiStatus {
            uiStatusByTxHash[tx.txHash] = uiStatus
        }
        if uiStatus.isTerminal {
            completedRecords[key] = tx.id
            stop(key: key)
        }
        return .answered
    }

    /// Network reads only; nothing here mutates tracking state, because the
    /// caller has not yet re-validated that the answer is still wanted.
    private func observe(
        tx: TransactionHistoryData,
        key: RecordKey,
        hash: String,
        sourceChain: Chain,
        network: Chain,
        isStillWanted: @MainActor () -> Bool
    ) async -> Observation {
        var observation = Observation()
        if !isSourceConfirmed(tx: tx, key: key, sourceChain: sourceChain, network: network) {
            let source: SourceObservation
            do {
                source = try await observeSource(txHash: tx.txHash, chain: sourceChain)
            } catch {
                logger.debug("[NATIVESWAP] Source status unavailable for \(tx.txHash, privacy: .public): \(error.localizedDescription, privacy: .public)")
                observation.unavailable = true
                return observation
            }
            switch source {
            case .confirmed:
                break
            case let .ended(status, reason):
                observation.status = status
                observation.failureReason = reason
                return observation
            case .waiting:
                return observation
            }
            guard isStillWanted() else { return observation }
        }
        observation.sourceConfirmed = true
        do {
            let response = try await httpClient.request(
                THORChainTransactionStatusAPI.getActions(txHash: hash, chain: network),
                responseType: THORChainActionsResponse.self
            ).data
            let outcome = Self.outcome(response: response, hash: hash)
            observation.status = outcome?.status
            observation.failureReason = outcome?.failureReason
            guard sourceChain == network, !Self.listsInbound(response, hash: hash), isStillWanted() else {
                return observation
            }
            if case let .rejected(reason) = try await nodeResult(txHash: hash, chain: network) {
                observation.status = Self.failedStatus
                observation.failureReason = reason
            }
        } catch {
            logger.debug("[NATIVESWAP] Status unavailable for \(tx.txHash, privacy: .public): \(error.localizedDescription, privacy: .public)")
            observation.unavailable = true
        }
        return observation
    }

    /// A deposit on the protocol network itself is answered by that network's
    /// Midgard in the second phase, `failed` included.
    private func isSourceConfirmed(tx: TransactionHistoryData, key: RecordKey, sourceChain: Chain, network: Chain) -> Bool {
        sourceChain == network
            || confirmedSources.contains(key)
            // The only non-terminal status ever persisted is a Midgard answer,
            // and Midgard indexes a deposit only once it has landed.
            || tx.swapTracking?.latestTrackingStatus != nil
    }

    /// The per-chain provider of a THORChain-family source reads Midgard and
    /// reports rate limits and 5xx as `.failed`, which would end a healthy swap
    /// on an outage, so that source's own Midgard is read here instead. A RUNE
    /// deposit bound for Maya that THORChain rejects or refunds is recorded
    /// there and never reaches Maya's Midgard.
    private func observeSource(txHash: String, chain: Chain) async throws -> SourceObservation {
        guard chain.chainType == .THORChain else {
            switch try await sourceStatus.checkTransactionStatus(txHash: txHash, chain: chain).status {
            case .confirmed: return .confirmed
            case let .failed(reason): return .ended(status: Self.failedStatus, failureReason: reason.trimmedNonEmpty)
            case .pending, .notFound: return .waiting
            }
        }
        let response = try await httpClient.request(
            THORChainTransactionStatusAPI.getActions(txHash: txHash, chain: chain),
            responseType: THORChainActionsResponse.self
        ).data
        guard Self.listsInbound(response, hash: txHash) else {
            if case let .rejected(reason) = try await nodeResult(txHash: txHash, chain: chain) {
                return .ended(status: Self.failedStatus, failureReason: reason)
            }
            return .waiting
        }
        // A truncated page could omit the `failed` or `refund` that outranks what it shows.
        guard let count = Int(response.count), count <= response.actions.count else { return .waiting }
        let matching = response.actions.filter { action in action.in.contains { Self.isSameTransaction($0.txID, txHash) } }
        if let failed = matching.first(where: { $0.type.lowercased() == Self.failedStatus }) {
            return .ended(status: Self.failedStatus, failureReason: failed.metadata?.failed?.reason?.trimmedNonEmpty)
        }
        if matching.contains(where: { $0.type.lowercased() == "refund" }) {
            return .ended(status: "refunded", failureReason: nil)
        }
        return .confirmed
    }

    /// A deposit the node rejects while executing it is committed with a
    /// non-zero code and never becomes a Midgard action, so the node is the
    /// only place that failure is visible. Asked only when Midgard lists nothing
    /// for the deposit. An accepted deposit is left to Midgard, which indexes
    /// it; a transaction not committed yet (404) is not an answer either way.
    private func nodeResult(txHash: String, chain: Chain) async throws -> NodeResult {
        guard let target = Self.nodeTransaction(hash: txHash, chain: chain) else { return .notRejected }
        let response: CosmosTransactionStatusResponse
        do {
            response = try await httpClient.request(target, responseType: CosmosTransactionStatusResponse.self).data
        } catch HTTPError.statusCode(404, _) {
            return .notRejected
        }
        guard let result = response.txResponse, result.code != 0 else { return .notRejected }
        return .rejected(reason: result.rawLog?.trimmedNonEmpty)
    }

    nonisolated static func nodeTransaction(hash: String, chain: Chain) -> TargetType? {
        let txHash = normalizedHash(hash)
        switch chain {
        case .thorChain:
            return ThorchainMainnetAPI(.transaction(hash: txHash))
        case .thorChainChainnet:
            return ThorchainStagenetAPI.transaction(env: .chainnet, hash: txHash)
        case .thorChainStagenet:
            return ThorchainStagenetAPI.transaction(env: .stagenet, hash: txHash)
        case .mayaChain:
            return MayaChainAPI(.transaction(hash: txHash))
        default:
            return nil
        }
    }

    /// Whether any action lists the deposit as its inbound. Maya's Midgard
    /// answers a hash it has never indexed with its unfiltered feed, so an empty
    /// page is not the only shape "nothing for this deposit" takes.
    private nonisolated static func listsInbound(_ response: THORChainActionsResponse, hash: String) -> Bool {
        response.actions.contains { action in action.in.contains { isSameTransaction($0.txID, hash) } }
    }

    // MARK: - Midgard outcome

    struct MidgardOutcome: Equatable {
        /// A status in the SwapKit tracking vocabulary the row already speaks.
        let status: String
        var failureReason: String?
    }

    /// Midgard's account of the inbound, or `nil` when there is no verdict yet.
    ///
    /// Same rules as Android and the SDK's `getSwapArrivalStatus`:
    /// - `failed` is final whatever its outbound is doing; it reads as a refund
    ///   once the refund outbound has been observed.
    /// - Anything still `pending` — a streaming swap, a refund not yet sent —
    ///   is in flight.
    /// - A settled `refund` is a refund; alongside a settled `swap` it is a
    ///   partial refund, which the row treats as refunded too: part of the input
    ///   came back unswapped, and that part is what Try again is for.
    /// - A settled `swap` alone is the only success.
    ///
    /// Unknown statuses, conflicting `swap`/`failed` evidence and a truncated
    /// page are not verdicts.
    nonisolated static func outcome(response: THORChainActionsResponse, hash: String) -> MidgardOutcome? {
        let matching = response.actions.filter { action in
            outcomeActionTypes.contains(action.type.lowercased())
                && action.in.contains { isSameTransaction($0.txID, hash) }
        }
        guard !matching.isEmpty,
              let count = Int(response.count), count <= response.actions.count else { return nil }
        let statuses = matching.map { $0.status.lowercased() }
        guard statuses.allSatisfy({ $0 == "success" || $0 == "pending" }) else { return nil }
        let types = Set(matching.map { $0.type.lowercased() })

        if types.contains("failed") {
            guard !types.contains("swap") else { return nil }
            let failed = matching.filter { $0.type.lowercased() == "failed" }
            let refundObserved = failed.contains { action in
                action.out.contains { !$0.txID.trimmingCharacters(in: .whitespaces).isEmpty }
            } || matching.contains { $0.type.lowercased() == "refund" && $0.status.lowercased() == "success" }
            if refundObserved { return MidgardOutcome(status: "refunded") }
            let reason = failed.lazy.compactMap { $0.metadata?.failed?.reason?.trimmedNonEmpty }.first
            return MidgardOutcome(status: failedStatus, failureReason: reason)
        }
        if statuses.contains("pending") { return MidgardOutcome(status: "swapping") }
        if types.contains("refund") {
            return MidgardOutcome(status: types.contains("swap") ? "partially_refunded" : "refunded")
        }
        return MidgardOutcome(status: "completed")
    }

    private nonisolated static let outcomeActionTypes: Set<String> = ["swap", "refund", "failed"]
    private nonisolated static let failedStatus = "failed"

    private nonisolated static func normalizedHash(_ hash: String) -> String {
        let value = hash.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.lowercased().hasPrefix("0x") ? String(value.dropFirst(2)) : value
    }

    /// Hex case is not semantic; base58 case is — two Solana signatures that
    /// differ only in case are different transactions.
    private nonisolated static func isSameTransaction(_ lhs: String, _ rhs: String) -> Bool {
        let lhs = normalizedHash(lhs)
        let rhs = normalizedHash(rhs)
        guard lhs.allSatisfy(\.isHexDigit), rhs.allSatisfy(\.isHexDigit) else { return lhs == rhs }
        return lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    /// Never faster than the source chain's own status cadence: a Bitcoin
    /// deposit gains nothing from a poll every ten seconds.
    nonisolated static func pollInterval(sourceChain: Chain?) -> TimeInterval {
        guard let sourceChain else { return baseInterval }
        return max(baseInterval, ChainStatusConfig.config(for: sourceChain).pollInterval)
    }

    // MARK: - Types

    private struct Observation {
        /// The source transaction is known to have landed.
        var sourceConfirmed = false
        var status: String?
        var failureReason: String?
        /// No answer at all: an HTTP error or an unreadable response.
        var unavailable = false
    }

    private enum NodeResult {
        case notRejected
        case rejected(reason: String?)
    }

    private enum SourceObservation {
        case waiting
        case confirmed
        /// The deposit never reached the protocol network.
        case ended(status: String, failureReason: String?)
    }

    /// `unavailable` backs the poll off; `answered` keeps the normal cadence.
    enum RefreshResult {
        case answered
        case unavailable
        case discarded
    }

    private struct RecordKey: Hashable {
        let vault: String
        let chain: String
        let hash: String

        init(_ tx: TransactionHistoryData) {
            vault = tx.pubKeyECDSA
            chain = tx.chainRawValue
            hash = tx.txHash
        }
    }

    private struct Poller {
        let tx: TransactionHistoryData
        var token = UUID()
        var task: Task<Void, Never>?
    }
}

// MARK: - Storage

/// The shared tracking writes plus the chain's reason for a failure, which
/// History shows after a reload.
@MainActor
protocol NativeSwapTrackingStorage: SwapTrackingStorage {
    func updateErrorMessage(txHash: String, pubKeyECDSA: String, errorMessage: String) throws
}

extension TransactionHistoryStorage: NativeSwapTrackingStorage {}

// MARK: - Which swaps are tracked

extension NativeSwapTrackingService {
    nonisolated static func metadata(broadcastHash: String, network: Chain) -> SwapTrackingMetadataData {
        SwapTrackingMetadataData(providerKind: providerKind, broadcastHash: broadcastHash, subProvider: network.rawValue)
    }

    /// Initiator side. `nil` for aggregator routes and for anything on a native
    /// route that is not a market swap (a SECURE+ mint rides a synthetic
    /// THORChain quote with no swap memo).
    nonisolated static func metadata(broadcastHash: String, quote: SwapQuote?) -> SwapTrackingMetadataData? {
        network(for: quote).map { metadata(broadcastHash: broadcastHash, network: $0) }
    }

    /// Co-signer side, which sees only the payload and the signed memo.
    nonisolated static func metadata(
        broadcastHash: String,
        payload: SwapPayload?,
        memo: String?
    ) -> SwapTrackingMetadataData? {
        network(for: payload, memo: memo).map { metadata(broadcastHash: broadcastHash, network: $0) }
    }

    /// The protocol network a native market swap settles on.
    nonisolated static func network(for quote: SwapQuote?) -> Chain? {
        switch quote {
        case let .thorchain(quote):
            return isMarketSwapMemo(quote.memo) ? .thorChain : nil
        case let .thorchainChainnet(quote):
            return isMarketSwapMemo(quote.memo) ? .thorChainChainnet : nil
        case let .thorchainStagenet(quote):
            return isMarketSwapMemo(quote.memo) ? .thorChainStagenet : nil
        case let .mayachain(quote):
            return isMarketSwapMemo(quote.memo) ? .mayaChain : nil
        case .oneinch, .kyberswap, .lifi, .swapkit, .jupiter, nil:
            return nil
        }
    }

    /// The payload alone is not enough: ERC20 LP adds and SECURE+ mints ride a
    /// THORChain payload too, for the router's `depositWithExpiry`.
    nonisolated static func network(for payload: SwapPayload?, memo: String?) -> Chain? {
        guard isMarketSwapMemo(memo) else { return nil }
        switch payload {
        case .thorchain: return .thorChain
        case .thorchainChainnet: return .thorChainChainnet
        case .thorchainStagenet: return .thorChainStagenet
        case .mayachain: return .mayaChain
        case .generic, .swapkit, nil: return nil
        }
    }

    /// `SWAP:`, `s:` or `=:`. A limit order (`=<:`), an LP add or a mint is
    /// indexed under another Midgard action type, so tracking one here would
    /// wait for a swap that never comes.
    nonisolated static func isMarketSwapMemo(_ memo: String?) -> Bool {
        guard let memo, let separator = memo.firstIndex(of: ":") else { return false }
        return ["=", "s", "swap"].contains(memo[..<separator].lowercased())
    }

    fileprivate nonisolated static func network(for tx: TransactionHistoryData) -> Chain? {
        guard tx.swapTracking?.providerKind == providerKind,
              let raw = tx.swapTracking?.subProvider, let chain = Chain(rawValue: raw),
              let hash = tx.swapTracking?.broadcastHash, !normalizedHash(hash).isEmpty else { return nil }
        switch chain {
        case .thorChain, .thorChainChainnet, .thorChainStagenet, .mayaChain: return chain
        default: return nil
        }
    }
}
