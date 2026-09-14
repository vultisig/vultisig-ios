import XCTest
@testable import VultisigApp

@MainActor
final class NativeSwapTrackingServiceTests: XCTestCase {
    func testProtocolNetworkAndNormalizedInboundLookupForBTCAndEVM() async {
        for network in [Chain.thorChain, .thorChainChainnet, .thorChainStagenet, .mayaChain] {
            for source in [Chain.bitcoin, .ethereum] {
                let tx = Self.transaction(hash: source == .bitcoin ? "abcdef" : "0xaBcDeF", source: source, network: network)
                let client = NativeSwapHTTPClient(payload: Self.response([Self.action(hash: "ABCDEF")]))
                let storage = NativeSwapStorage(rows: [tx])
                let service = NativeSwapTrackingService(httpClient: client, storage: storage)
                await service.forceRefresh(tx: tx)
                let request = await client.lastRequest
                XCTAssertEqual(request?.hash, "ABCDEF")
                XCTAssertEqual(request?.network, network)
                XCTAssertNil(tx.swapTracking?.sourceChainId)
                XCTAssertEqual(storage.statuses, ["completed"])
            }
        }
    }

    func testPendingStreamingThenCompleted() async {
        let tx = Self.transaction()
        let storage = NativeSwapStorage(rows: [tx])
        let client = NativeSwapHTTPClient(payload: Self.response([
            Self.action(status: "success"), Self.action(status: "pending")
        ]))
        let service = NativeSwapTrackingService(httpClient: client, storage: storage)
        await service.forceRefresh(tx: tx)
        XCTAssertEqual(storage.statuses, ["swapping"])
        XCTAssertEqual(service.uiStatusByTxHash[tx.txHash], .swapping)
        await client.setPayload(Self.response([Self.action()]))
        await service.forceRefresh(tx: tx)
        XCTAssertEqual(storage.statuses, ["swapping", "completed"])
    }

    func testRefundPartialRefundAndAuthoritativeFailure() async {
        let cases: [([String], String, SwapTrackingUiStatus)] = [
            (["refund"], "refunded", .refunded),
            (["swap", "refund"], "partially_refunded", .refunded),
            (["failed"], "failed", .failed)
        ]
        for (types, expected, uiStatus) in cases {
            let tx = Self.transaction()
            let storage = NativeSwapStorage(rows: [tx])
            let client = NativeSwapHTTPClient(payload: Self.response(types.map { Self.action(type: $0) }))
            let service = NativeSwapTrackingService(httpClient: client, storage: storage)
            await service.forceRefresh(tx: tx)
            XCTAssertEqual(storage.statuses, [expected])
            XCTAssertEqual(service.uiStatusByTxHash[tx.txHash], uiStatus)
        }
    }

    func testPendingRefundDoesNotEndPartiallyExecutedSwap() async {
        let tx = Self.transaction()
        let storage = NativeSwapStorage(rows: [tx])
        let client = NativeSwapHTTPClient(payload: Self.response([
            Self.action(), Self.action(type: "refund", status: "pending")
        ]))
        let service = NativeSwapTrackingService(httpClient: client, storage: storage)
        await service.forceRefresh(tx: tx)
        XCTAssertEqual(storage.statuses, ["swapping"])
    }

    func testUnknownUnrelatedNonmatchingAndIncompleteResponsesOnlyTouchFreshness() async {
        let responses = [
            Self.response([]),
            Self.response([Self.action(type: "contract")]),
            Self.response([Self.action(hash: "OTHER")]),
            Self.response([Self.action(status: "unknown")]),
            Self.response([Self.action(status: "failed")]),
            Self.response([Self.action(), Self.action(type: "failed")]),
            Self.response([Self.action()], count: "2")
        ]
        for response in responses {
            let tx = Self.transaction()
            let storage = NativeSwapStorage(rows: [tx])
            let service = NativeSwapTrackingService(httpClient: NativeSwapHTTPClient(payload: response), storage: storage)
            await service.forceRefresh(tx: tx)
            XCTAssertTrue(storage.statuses.isEmpty)
            XCTAssertEqual(storage.touches.count, 1)
            XCTAssertTrue(service.uiStatusByTxHash.isEmpty)
        }
    }

    func testOutageNeverBecomesFailedAsClockAdvances() async {
        let tx = Self.transaction()
        let storage = NativeSwapStorage(rows: [tx])
        let client = NativeSwapHTTPClient(payload: Data(), fails: true)
        var now = Date(timeIntervalSince1970: 100)
        let service = NativeSwapTrackingService(httpClient: client, storage: storage, clock: { now })
        for _ in 0..<3 {
            await service.forceRefresh(tx: tx, backgroundObservation: true)
            now = now.addingTimeInterval(86_400)
        }
        XCTAssertTrue(storage.statuses.isEmpty)
        XCTAssertEqual(storage.touches.count, 3)
        XCTAssertEqual(storage.touches.last, Date(timeIntervalSince1970: 172_900))
    }

    func testCancellationDiscardsLateSuccessAndError() async {
        for fails in [false, true] {
            let tx = Self.transaction()
            let storage = NativeSwapStorage(rows: [tx])
            let client = NativeSwapHTTPClient(payload: Self.response([Self.action()]), fails: fails, suspended: true)
            let service = NativeSwapTrackingService(httpClient: client, storage: storage)
            let task = Task { await service.forceRefresh(tx: tx) }
            await client.waitUntilRequested()
            task.cancel()
            await client.release()
            await task.value
            XCTAssertTrue(storage.statuses.isEmpty)
            XCTAssertTrue(storage.touches.isEmpty)
            XCTAssertTrue(service.uiStatusByTxHash.isEmpty)
        }
    }

    func testEligibilityInvalidationDiscardsLateResponse() async {
        for fails in [false, true] {
            let tx = Self.transaction()
            let storage = NativeSwapStorage(rows: [tx])
            let client = NativeSwapHTTPClient(payload: Self.response([Self.action()]), fails: fails, suspended: true)
            let service = NativeSwapTrackingService(httpClient: client, storage: storage)
            var eligible = true
            let task = Task { await service.forceRefresh(tx: tx, shouldApply: { eligible }) }
            await client.waitUntilRequested()
            eligible = false
            await client.release()
            await task.value
            XCTAssertTrue(storage.statuses.isEmpty)
            XCTAssertTrue(storage.touches.isEmpty)
        }
    }

    func testResetInvalidatesUnregisteredOneShot() async {
        let tx = Self.transaction()
        let storage = NativeSwapStorage(rows: [tx])
        let client = NativeSwapHTTPClient(payload: Self.response([Self.action()]), suspended: true)
        let service = NativeSwapTrackingService(httpClient: client, storage: storage)
        let task = Task { await service.forceRefresh(tx: tx) }
        await client.waitUntilRequested()
        service.stopAllTracking()
        await client.release()
        await task.value
        XCTAssertTrue(storage.statuses.isEmpty)
        XCTAssertTrue(service.uiStatusByTxHash.isEmpty)
    }

    func testDeletedOrReplacedRowDiscardsLateResponse() async {
        for replacement in [false, true] {
            let tx = Self.transaction()
            let storage = NativeSwapStorage(rows: [tx])
            let client = NativeSwapHTTPClient(payload: Self.response([Self.action()]), suspended: true)
            let service = NativeSwapTrackingService(httpClient: client, storage: storage)
            let task = Task { await service.forceRefresh(tx: tx) }
            await client.waitUntilRequested()
            storage.rows = replacement ? [Self.transaction()] : []
            await client.release()
            await task.value
            XCTAssertTrue(storage.statuses.isEmpty)
            XCTAssertTrue(storage.touches.isEmpty)
        }
    }

    func testBackgroundTerminalRemovesPausedPollerAndRejectsStaleRestart() async {
        let tx = Self.transaction()
        let storage = NativeSwapStorage(rows: [tx])
        let client = NativeSwapHTTPClient(payload: Self.response([Self.action()]))
        let service = NativeSwapTrackingService(httpClient: client, storage: storage)
        service.setActive(false)
        service.start(tx: tx)
        await service.forceRefresh(tx: tx, backgroundObservation: true)
        XCTAssertEqual(service.trackedSwapCountForTesting, 0)
        service.start(tx: tx)
        service.setActive(true)
        await service.forceRefresh(tx: tx)
        for _ in 0..<10 { await Task.yield() }
        let requests = await client.requestCount
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(storage.statuses, ["completed"])
        XCTAssertEqual(service.uiStatusByTxHash[tx.txHash], .completed)
        service.stopAllTracking()
    }

    func testPauseInvalidatesRunningPollerResponse() async {
        let tx = Self.transaction()
        let storage = NativeSwapStorage(rows: [tx])
        let client = NativeSwapHTTPClient(payload: Self.response([Self.action()]), suspended: true)
        let service = NativeSwapTrackingService(httpClient: client, storage: storage)
        service.start(tx: tx)
        await client.waitUntilRequested()
        service.setActive(false)
        await client.release()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(storage.statuses.isEmpty)
        XCTAssertEqual(service.trackedSwapCountForTesting, 1)
        service.stopAllTracking()
    }

    func testSameHashInDifferentVaultsCompletesEachRecord() async {
        let first = Self.transaction(vault: "first")
        let second = Self.transaction(vault: "second")
        let storage = NativeSwapStorage(rows: [first, second])
        let client = NativeSwapHTTPClient(payload: Self.response([Self.action()]))
        let service = NativeSwapTrackingService(httpClient: client, storage: storage)
        service.setActive(false)
        service.start(tx: first)
        service.start(tx: second)
        await service.forceRefresh(tx: first, backgroundObservation: true)
        XCTAssertEqual(service.trackedSwapCountForTesting, 1)
        await service.forceRefresh(tx: second, backgroundObservation: true)
        XCTAssertEqual(service.trackedSwapCountForTesting, 0)
        XCTAssertEqual(storage.statuses, ["completed", "completed"])
        XCTAssertTrue(storage.rows.isEmpty)
        service.stopAllTracking()
    }

    func testResumeUsesCompositeIdentityAndOnlySupportedProtocolMetadata() async {
        let rows = [
            Self.transaction(vault: "first"), Self.transaction(vault: "second"),
            Self.transaction(source: .bitcoin), Self.transaction(network: .ethereum),
            Self.transaction(provider: "swapKit")
        ]
        let storage = NativeSwapStorage(rows: rows)
        let service = NativeSwapTrackingService(httpClient: NativeSwapHTTPClient(payload: Self.response([])), storage: storage)
        service.setActive(false)
        await service.resumeInFlight()
        XCTAssertEqual(service.trackedSwapCountForTesting, 3)
        service.stopAllTracking()
        XCTAssertEqual(service.trackedSwapCountForTesting, 0)
        XCTAssertTrue(service.uiStatusByTxHash.isEmpty)
    }

    private static func transaction(
        hash: String = "0xabcdef", vault: String = "vault", source: Chain = .ethereum,
        network: Chain = .thorChain, provider: String = NativeSwapTrackingService.providerKind
    ) -> TransactionHistoryData {
        TransactionHistoryData(
            id: UUID(), txHash: hash, approveTxHash: nil, pubKeyECDSA: vault, type: .swap, status: .inProgress,
            chainRawValue: source.rawValue, coinTicker: "ETH", coinLogo: "eth", coinChainLogo: nil,
            amountCrypto: "1", amountFiat: "2000", fromAddress: "from", toAddress: "to",
            toCoinTicker: "BTC", toCoinLogo: "btc", toCoinChainLogo: nil, toAmountCrypto: "0.02",
            toAmountFiat: "2000", swapProvider: "THORChain", feeCrypto: "0", feeFiat: "0",
            network: source.rawValue, explorerLink: "", createdAt: Date(), completedAt: nil,
            estimatedTime: nil, errorMessage: nil,
            swapTracking: provider == NativeSwapTrackingService.providerKind
                ? NativeSwapTrackingService.metadata(broadcastHash: hash, network: network)
                : SwapTrackingMetadataData(providerKind: provider, broadcastHash: hash, subProvider: network.rawValue)
        )
    }

    private static func action(type: String = "swap", status: String = "success", hash: String = "ABCDEF") -> [String: Any] {
        ["type": type, "status": status, "pools": [], "in": [["txID": hash]],
         "out": [["txID": "OUTBOUND"]], "date": "1", "height": "1"]
    }

    private static func response(_ actions: [[String: Any]], count: String? = nil) -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: ["actions": actions, "count": count ?? String(actions.count)])
        } catch {
            XCTFail("Invalid fixture: \(error)")
            return Data()
        }
    }
}

private actor NativeSwapHTTPClient: HTTPClientProtocol {
    private var payload: Data
    private let fails: Bool
    private let suspended: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    private(set) var requestCount = 0
    private(set) var lastRequest: (hash: String, network: Chain)?

    init(payload: Data, fails: Bool = false, suspended: Bool = false) {
        self.payload = payload
        self.fails = fails
        self.suspended = suspended
    }

    func setPayload(_ payload: Data) { self.payload = payload }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        if let api = target as? THORChainTransactionStatusAPI, case let .getActions(hash, chain) = api {
            lastRequest = (hash, chain)
        }
        requestCount += 1
        for observer in observers { observer.resume() }
        observers.removeAll()
        if suspended { await withCheckedContinuation { continuation = $0 } }
        if fails { throw URLError(.notConnectedToInternet) }
        return HTTPResponse(data: payload, response: HTTPURLResponse(
            url: URL(string: "https://native-swap.invalid")!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!)
    }

    func waitUntilRequested() async {
        if requestCount == 0 { await withCheckedContinuation { observers.append($0) } }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class NativeSwapStorage: SwapTrackingStorage {
    var rows: [TransactionHistoryData]
    var statuses: [String] = []
    var touches: [Date] = []

    init(rows: [TransactionHistoryData]) { self.rows = rows }

    func fetchInFlightSwapTracking(providerKind: String) throws -> [TransactionHistoryData] {
        rows.filter { $0.swapTracking?.providerKind == providerKind && !$0.swapTrackingUiStatus.isTerminal }
    }

    func updateSwapTrackingStatus(
        txHash: String, pubKeyECDSA: String, latestStatus _: String?, latestTrackingStatus: String?,
        uiStatus: SwapTrackingUiStatus, polledAt _: Date
    ) throws {
        statuses.append(latestTrackingStatus ?? "")
        if uiStatus.isTerminal { rows.removeAll { $0.txHash == txHash && $0.pubKeyECDSA == pubKeyECDSA } }
    }

    func touchSwapTrackingLastPolled(txHash _: String, pubKeyECDSA _: String, polledAt: Date) throws {
        touches.append(polledAt)
    }
}
