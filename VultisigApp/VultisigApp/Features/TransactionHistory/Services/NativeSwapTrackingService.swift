import Foundation

/// Tracks native market swaps on their protocol network, including BTC/EVM inbounds.
/// Indexer availability is freshness information; it never proves a failed swap.
@MainActor
final class NativeSwapTrackingService: ObservableObject, SwapTrackingService {
    nonisolated static let providerKind = "nativeSwap"
    static let shared = NativeSwapTrackingService(httpClient: HTTPClient(), storage: TransactionHistoryStorage.shared)

    @Published private(set) var uiStatusByTxHash: [String: SwapTrackingUiStatus] = [:]

    private let httpClient: HTTPClientProtocol
    private let storage: SwapTrackingStorage
    private let clock: () -> Date
    private var isActive = true
    private var generation = UUID()
    private var pollers: [RecordKey: Poller] = [:]
    private var requests: [RecordKey: UUID] = [:]
    private var completedRecords: [RecordKey: UUID] = [:]

    init(httpClient: HTTPClientProtocol, storage: SwapTrackingStorage, clock: @escaping () -> Date = Date.init) {
        self.httpClient = httpClient
        self.storage = storage
        self.clock = clock
    }

    nonisolated static func metadata(broadcastHash: String, network: Chain) -> SwapTrackingMetadataData {
        SwapTrackingMetadataData(providerKind: providerKind, broadcastHash: broadcastHash, subProvider: network.rawValue)
    }

    func start(tx: TransactionHistoryData) {
        guard Self.network(for: tx) != nil else { return }
        let key = RecordKey(tx)
        guard completedRecords[key] != tx.id else { return }
        uiStatusByTxHash[tx.txHash] = tx.swapTrackingUiStatus
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
        guard !Task.isCancelled,
              let rows = try? storage.fetchInFlightSwapTracking(providerKind: Self.providerKind) else { return }
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
        uiStatusByTxHash.removeAll()
    }

    /// Background and foreground observations use the same conservative outcome rules.
    func forceRefresh(
        tx: TransactionHistoryData,
        backgroundObservation: Bool = false,
        shouldApply: @escaping @MainActor () -> Bool = { true }
    ) async {
        _ = backgroundObservation
        await refresh(tx: tx, shouldApply: shouldApply)
    }

    var trackedSwapCountForTesting: Int { pollers.count }

    func pollingTaskForTesting(tx: TransactionHistoryData) -> Task<Void, Never>? { pollers[RecordKey(tx)]?.task }

    private func spawn(key: RecordKey) {
        guard let entry = pollers[key], entry.task == nil else { return }
        let token = entry.token
        pollers[key]?.task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isActive, self.pollers[key]?.token == token else { return }
                await self.refresh(tx: entry.tx, shouldApply: { [weak self] in
                    self?.isActive == true && self?.pollers[key]?.token == token
                })
                guard !Task.isCancelled, self.isActive, self.pollers[key]?.token == token else { return }
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                guard !Task.isCancelled, self.isActive, self.pollers[key]?.token == token else { return }
            }
        }
    }

    private func stop(key: RecordKey) {
        pollers.removeValue(forKey: key)?.task?.cancel()
        requests.removeValue(forKey: key)
    }

    private func refresh(tx: TransactionHistoryData, shouldApply: @MainActor () -> Bool) async {
        let key = RecordKey(tx)
        guard !Task.isCancelled, shouldApply(), !tx.swapTrackingUiStatus.isTerminal,
              completedRecords[key] != tx.id,
              let network = Self.network(for: tx), let hash = tx.swapTracking?.broadcastHash else { return }
        let request = UUID()
        let capturedGeneration = generation
        requests[key] = request
        let response: THORChainActionsResponse?
        do {
            response = try await httpClient.request(
                THORChainTransactionStatusAPI.getActions(txHash: Self.normalizedHash(hash), chain: network),
                responseType: THORChainActionsResponse.self
            ).data
        } catch {
            response = nil
        }
        // The HTTP client may finish after cancellation, reset, another refresh, or a
        // vault/history change. Re-read the row before writing either outcome or freshness.
        guard !Task.isCancelled, generation == capturedGeneration, requests[key] == request, shouldApply() else { return }
        requests.removeValue(forKey: key)
        guard let rows = try? storage.fetchInFlightSwapTracking(providerKind: Self.providerKind) else { return }
        guard rows.contains(where: {
                  $0.id == tx.id && RecordKey($0) == key && !$0.swapTrackingUiStatus.isTerminal
                      && Self.network(for: $0) == network && $0.swapTracking?.broadcastHash == hash
              }) else {
            stop(key: key)
            return
        }
        let now = clock()
        guard let response, let status = Self.outcome(response: response, hash: hash) else {
            try? storage.touchSwapTrackingLastPolled(txHash: tx.txHash, pubKeyECDSA: tx.pubKeyECDSA, polledAt: now)
            return
        }
        let uiStatus = SwapKitTrackingStatusMapper.map(trackingStatus: status)
        do {
            try storage.updateSwapTrackingStatus(
                txHash: tx.txHash, pubKeyECDSA: tx.pubKeyECDSA,
                latestStatus: status, latestTrackingStatus: status, uiStatus: uiStatus, polledAt: now
            )
        } catch { return }
        uiStatusByTxHash[tx.txHash] = uiStatus
        if uiStatus.isTerminal {
            completedRecords[key] = tx.id
            stop(key: key)
        }
    }

    private static func network(for tx: TransactionHistoryData) -> Chain? {
        guard tx.swapTracking?.providerKind == providerKind,
              let raw = tx.swapTracking?.subProvider, let chain = Chain(rawValue: raw),
              let hash = tx.swapTracking?.broadcastHash, !normalizedHash(hash).isEmpty else { return nil }
        switch chain {
        case .thorChain, .thorChainChainnet, .thorChainStagenet, .mayaChain: return chain
        default: return nil
        }
    }

    private static func normalizedHash(_ hash: String) -> String {
        let value = hash.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return value.hasPrefix("0X") ? String(value.dropFirst(2)) : value
    }

    private static func outcome(response: THORChainActionsResponse, hash: String) -> String? {
        let matching = response.actions.filter { action in
            ["swap", "refund", "failed"].contains(action.type.lowercased())
                && action.in.contains { normalizedHash($0.txID) == normalizedHash(hash) }
        }
        guard !matching.isEmpty else { return nil }
        // A partial streaming execution or unfinished refund is still in flight,
        // even when another action for this inbound already has an outbound.
        if matching.contains(where: { $0.status.lowercased() == "pending" }) { return "swapping" }
        guard matching.allSatisfy({ $0.status.lowercased() == "success" }),
              let count = Int(response.count), count <= response.actions.count else { return nil }
        let types = Set(matching.map { $0.type.lowercased() })
        if types.contains("swap"), types.contains("refund") { return "partially_refunded" }
        if types.contains("refund") { return "refunded" }
        // Conflicting failed/swap evidence is not a fully established outcome.
        if types.contains("swap"), types.contains("failed") { return nil }
        if types.contains("swap") { return "completed" }
        if types == ["failed"] { return "failed" }
        return nil
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
