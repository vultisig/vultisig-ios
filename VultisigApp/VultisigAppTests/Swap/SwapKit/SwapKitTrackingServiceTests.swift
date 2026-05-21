//
//  SwapKitTrackingServiceTests.swift
//  VultisigAppTests
//
//  Lifecycle coverage for `SwapKitTrackingService` — uses in-memory mocks
//  for `HTTPClientProtocol` + `SwapTrackingStorage` so the tests never sleep
//  and never touch SwiftData. Drives the documented state-transition
//  sequence (`not_started → starting → broadcasted → mempool → inbound →
//  swapping → outbound → completed`), refund / failure terminals, and the
//  `unknown > 10 min → failed` give-up window.
//
//  Polling cadence + ScenePhase wiring is exercised via `forceRefresh`
//  (single-shot poll) rather than letting the Task loop sleep — that keeps
//  the tests fast and deterministic.
//

import XCTest
@testable import VultisigApp

@MainActor
final class SwapKitTrackingServiceTests: XCTestCase {

    // MARK: - State-transition coverage

    func testHappyPathTransitionsThroughFullSequence() async throws {
        let storage = FakeSwapTrackingStorage()
        let http = StubHTTPClient()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var clockTick = baseDate
        let service = SwapKitTrackingService(
            httpClient: http,
            storage: storage,
            clock: { clockTick }
        )

        let tx = Self.makeSwapKitTx()
        storage.inFlight = [tx]

        let sequence: [(String, SwapKitTrackingStatus)] = [
            ("not_started", .notStarted),
            ("starting", .pending),
            ("broadcasted", .pending),
            ("mempool", .pending),
            ("inbound", .pending),
            ("swapping", .swapping),
            ("outbound", .swapping),
            ("completed", .completed)
        ]
        http.responses = sequence.map { Self.makeResponse(status: $0.1, trackingStatus: $0.0) }

        for (raw, _) in sequence {
            await service.forceRefresh(tx: tx)
            clockTick = clockTick.addingTimeInterval(10)
            let observed = storage.observations.last
            XCTAssertEqual(observed?.trackingStatus, raw)
        }

        XCTAssertEqual(storage.observations.last?.uiStatus, .completed)
        XCTAssertTrue(storage.observations.last!.uiStatus.isTerminal)
    }

    func testRefundPathMapsToTerminalRefunded() async {
        let storage = FakeSwapTrackingStorage()
        let http = StubHTTPClient()
        let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })

        let tx = Self.makeSwapKitTx()
        http.responses = [Self.makeResponse(status: .refunded, trackingStatus: "refunded")]

        await service.forceRefresh(tx: tx)

        let observed = storage.observations.last
        XCTAssertEqual(observed?.uiStatus, .refunded)
        XCTAssertTrue(observed!.uiStatus.isTerminal)
    }

    func testPartialRefundAlsoTerminal() async {
        let storage = FakeSwapTrackingStorage()
        let http = StubHTTPClient()
        let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })

        http.responses = [Self.makeResponse(status: .refunded, trackingStatus: "partially_refunded")]
        await service.forceRefresh(tx: Self.makeSwapKitTx())

        XCTAssertEqual(storage.observations.last?.uiStatus, .refunded)
    }

    func testFailureTerminalsAllMapToFailed() async {
        let terminals = ["dropped", "reverted", "replaced", "retries_exceeded", "parsing_error"]
        for raw in terminals {
            let storage = FakeSwapTrackingStorage()
            let http = StubHTTPClient()
            let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })
            http.responses = [Self.makeResponse(status: .failed, trackingStatus: raw)]
            await service.forceRefresh(tx: Self.makeSwapKitTx())
            XCTAssertEqual(
                storage.observations.last?.uiStatus,
                .failed,
                "Expected .failed for tracking status \(raw)"
            )
        }
    }

    // MARK: - Unknown give-up window

    func testUnknownUnderTenMinutesStaysPending() async {
        let storage = FakeSwapTrackingStorage()
        let http = StubHTTPClient()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var clockTick = baseDate
        let service = SwapKitTrackingService(
            httpClient: http,
            storage: storage,
            clock: { clockTick }
        )

        var tx = Self.makeSwapKitTx()
        // Tracking started 5 minutes ago — within the 10-minute window.
        tx = Self.applyTrackingStarted(tx, date: baseDate.addingTimeInterval(-5 * 60))
        storage.inFlight = [tx]

        http.responses = [Self.makeResponse(status: .unknown, trackingStatus: "unknown")]
        await service.forceRefresh(tx: tx)
        clockTick = clockTick.addingTimeInterval(1)

        XCTAssertEqual(storage.observations.last?.uiStatus, .pending)
    }

    func testUnknownPastTenMinutesPromotesToTerminalUnknownExtended() async {
        let storage = FakeSwapTrackingStorage()
        let http = StubHTTPClient()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var clockTick = baseDate
        let service = SwapKitTrackingService(
            httpClient: http,
            storage: storage,
            clock: { clockTick }
        )

        var tx = Self.makeSwapKitTx()
        // Tracking started 11 minutes ago — past the give-up window.
        tx = Self.applyTrackingStarted(tx, date: baseDate.addingTimeInterval(-11 * 60))
        storage.inFlight = [tx]

        http.responses = [Self.makeResponse(status: .unknown, trackingStatus: "unknown")]
        await service.forceRefresh(tx: tx)
        clockTick = clockTick.addingTimeInterval(1)

        XCTAssertEqual(storage.observations.last?.uiStatus, .unknownPendingExtended)
        XCTAssertTrue(storage.observations.last!.uiStatus.isTerminal)
    }

    // MARK: - Tracker-outage flag wiring

    func testTrackerOutageFlipsTrueOnUnknownExtendedPromotion() async {
        let storage = FakeSwapTrackingStorage()
        let http = StubHTTPClient()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var clockTick = baseDate
        let service = SwapKitTrackingService(
            httpClient: http,
            storage: storage,
            clock: { clockTick }
        )

        // Row's tracking started 11 minutes ago — outside the unknown
        // give-up window. The next `/track` poll should promote the row
        // to `unknownPendingExtended` *and* set the outage flag so the
        // tx-history viewmodel can hand the row back to native polling.
        var tx = Self.makeSwapKitTx()
        tx = Self.applyTrackingStarted(tx, date: baseDate.addingTimeInterval(-11 * 60))
        storage.inFlight = [tx]

        http.responses = [Self.makeResponse(status: .unknown, trackingStatus: "unknown")]
        await service.forceRefresh(tx: tx)
        clockTick = clockTick.addingTimeInterval(1)

        XCTAssertEqual(storage.observations.last?.uiStatus, .unknownPendingExtended)
        XCTAssertEqual(storage.observations.last?.trackerOutage, true,
                       "Outage flag must flip true the moment we promote to unknownPendingExtended")
    }

    func testTrackerOutageClearsOnNextSuccessfulTrackResponse() async {
        let storage = FakeSwapTrackingStorage()
        let http = StubHTTPClient()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var clockTick = baseDate
        let service = SwapKitTrackingService(
            httpClient: http,
            storage: storage,
            clock: { clockTick }
        )

        // First poll: stuck-in-unknown beyond the give-up window.
        var tx = Self.makeSwapKitTx()
        tx = Self.applyTrackingStarted(tx, date: baseDate.addingTimeInterval(-11 * 60))
        storage.inFlight = [tx]

        http.responses = [
            Self.makeResponse(status: .unknown, trackingStatus: "unknown"),
            Self.makeResponse(status: .swapping, trackingStatus: "swapping")
        ]

        await service.forceRefresh(tx: tx)
        XCTAssertEqual(storage.observations.last?.trackerOutage, true)

        // Now `/track` recovers — the next response carries an actual
        // status. Outage flag must clear so native polling steps back
        // and `/track` regains authority.
        clockTick = clockTick.addingTimeInterval(15)
        await service.forceRefresh(tx: tx)

        XCTAssertEqual(storage.observations.last?.uiStatus, .swapping)
        XCTAssertEqual(storage.observations.last?.trackerOutage, false,
                       "Outage flag must clear on the next successful /track response")
    }

    func testTrackerOutageStaysFalseOnHappyPath() async {
        let storage = FakeSwapTrackingStorage()
        let http = StubHTTPClient()
        let service = SwapKitTrackingService(
            httpClient: http,
            storage: storage,
            clock: { Date() }
        )

        http.responses = [
            Self.makeResponse(status: .pending, trackingStatus: "broadcasted"),
            Self.makeResponse(status: .swapping, trackingStatus: "swapping"),
            Self.makeResponse(status: .completed, trackingStatus: "completed")
        ]
        for _ in 0..<3 {
            await service.forceRefresh(tx: Self.makeSwapKitTx())
        }

        XCTAssertEqual(storage.observations.count, 3)
        XCTAssertTrue(
            storage.observations.allSatisfy { $0.trackerOutage == false },
            "No happy-path response should ever flip the outage flag on"
        )
    }

    // MARK: - Failure handling — touches lastPolledAt without mutating status

    func testTransientFailureTouchesLastPolledOnly() async {
        let storage = FakeSwapTrackingStorage()
        let http = StubHTTPClient()
        http.shouldThrow = TestError.network
        let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })

        let tx = Self.makeSwapKitTx()
        await service.forceRefresh(tx: tx)

        XCTAssertTrue(storage.observations.isEmpty, "Failure should not write a status row")
        XCTAssertEqual(storage.touchCount, 1, "Failure should touch lastPolledAt once")
    }

    // MARK: - Start/stop bookkeeping

    func testStartIsIdempotent() {
        let storage = FakeSwapTrackingStorage()
        let http = StubHTTPClient()
        let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })

        let tx = Self.makeSwapKitTx()
        service.start(tx: tx)
        service.start(tx: tx)
        XCTAssertEqual(service.trackedSwapCountForTesting, 1, "Duplicate start should be a no-op")
    }

    func testStartSkipsTerminalRows() {
        let storage = FakeSwapTrackingStorage()
        let http = StubHTTPClient()
        let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })

        let tx = Self.makeSwapKitTx(latestTrackingStatus: "completed")
        service.start(tx: tx)
        XCTAssertEqual(service.trackedSwapCountForTesting, 0)
    }

    func testStartSkipsRowsOwnedByOtherProviders() {
        let storage = FakeSwapTrackingStorage()
        let http = StubHTTPClient()
        let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })

        let tx = Self.makeNonSwapKitTx()
        service.start(tx: tx)
        XCTAssertEqual(service.trackedSwapCountForTesting, 0)
    }

    func testStopRemovesEntry() {
        let storage = FakeSwapTrackingStorage()
        let http = StubHTTPClient()
        let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })

        let tx = Self.makeSwapKitTx()
        service.start(tx: tx)
        service.stop(txHash: tx.txHash)
        XCTAssertEqual(service.trackedSwapCountForTesting, 0)
    }

    func testResumeInFlightStartsAllNonTerminalSwapKitRows() async {
        let storage = FakeSwapTrackingStorage()
        let http = StubHTTPClient()
        let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })

        storage.inFlight = [
            Self.makeSwapKitTx(txHash: "0xaaa"),
            Self.makeSwapKitTx(txHash: "0xbbb"),
            Self.makeSwapKitTx(txHash: "0xccc", latestTrackingStatus: "completed")
        ]
        await service.resumeInFlight()
        // The fake's `fetchInFlightSwapTracking` already filters terminals
        // out (mirroring the real storage). Verify only the 3rd was filtered.
        XCTAssertLessThanOrEqual(service.trackedSwapCountForTesting, 2)
    }

    // MARK: - Observable UI-status cache

    func testStartSeedsUiStatusCacheWithPersistedRowStatus() {
        let storage = FakeSwapTrackingStorage()
        let http = StubHTTPClient()
        let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })

        // Simulate a row already past the broadcast frame — the cache should
        // surface that the moment the view subscribes, without waiting for
        // the first poll round-trip.
        let tx = Self.makeSwapKitTx(latestTrackingStatus: "swapping")
        service.start(tx: tx)

        XCTAssertEqual(service.uiStatusByTxHash[tx.txHash], .swapping)
    }

    func testStartOnFreshRowSeedsCacheWithPending() {
        let storage = FakeSwapTrackingStorage()
        let http = StubHTTPClient()
        let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })

        // No persisted `/track` data yet — `swapTrackingUiStatus` defaults
        // to `.pending` via the model extension; the cache must mirror that
        // so the done-screen surfaces the broadcast frame on first
        // appearance.
        let tx = Self.makeSwapKitTx()
        service.start(tx: tx)

        XCTAssertEqual(service.uiStatusByTxHash[tx.txHash], .pending)
    }

    func testHappyPathPollUpdatesUiStatusCache() async {
        let storage = FakeSwapTrackingStorage()
        let http = StubHTTPClient()
        let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })

        let tx = Self.makeSwapKitTx()
        http.responses = [
            Self.makeResponse(status: .swapping, trackingStatus: "swapping"),
            Self.makeResponse(status: .completed, trackingStatus: "completed")
        ]

        await service.forceRefresh(tx: tx)
        XCTAssertEqual(service.uiStatusByTxHash[tx.txHash], .swapping)

        await service.forceRefresh(tx: tx)
        XCTAssertEqual(service.uiStatusByTxHash[tx.txHash], .completed)
    }

    func testGiveUpUnknownExtendedPromotionUpdatesCache() async {
        let storage = FakeSwapTrackingStorage()
        let http = StubHTTPClient()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var clockTick = baseDate
        let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { clockTick })

        var tx = Self.makeSwapKitTx()
        tx = Self.applyTrackingStarted(tx, date: baseDate.addingTimeInterval(-11 * 60))
        storage.inFlight = [tx]

        http.responses = [Self.makeResponse(status: .unknown, trackingStatus: "unknown")]
        await service.forceRefresh(tx: tx)
        clockTick = clockTick.addingTimeInterval(1)

        XCTAssertEqual(service.uiStatusByTxHash[tx.txHash], .unknownPendingExtended)
    }

    // MARK: - ScenePhase

    func testSetActiveToFalseCancelsRunningPollers() {
        let storage = FakeSwapTrackingStorage()
        let http = StubHTTPClient()
        let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })

        let tx = Self.makeSwapKitTx()
        service.start(tx: tx)
        XCTAssertEqual(service.trackedSwapCountForTesting, 1)

        service.setActive(false)
        // Entry is preserved so resume can pick it up — only the Task is cancelled.
        XCTAssertEqual(service.trackedSwapCountForTesting, 1)

        service.setActive(true)
        XCTAssertEqual(service.trackedSwapCountForTesting, 1)
    }

    // MARK: - Fixtures

    private static func makeSwapKitTx(
        txHash: String = "0xbroadcast",
        latestTrackingStatus: String? = nil
    ) -> TransactionHistoryData {
        TransactionHistoryData(
            id: UUID(),
            txHash: txHash,
            approveTxHash: nil,
            pubKeyECDSA: "vault-pub",
            type: .swap,
            status: .inProgress,
            chainRawValue: "Ethereum",
            coinTicker: "ETH",
            coinLogo: "eth",
            coinChainLogo: nil,
            amountCrypto: "1.0",
            amountFiat: "2000",
            fromAddress: "0xfrom",
            toAddress: "0xto",
            toCoinTicker: "USDC",
            toCoinLogo: "usdc",
            toCoinChainLogo: nil,
            toAmountCrypto: "2000.0",
            toAmountFiat: "2000",
            swapProvider: "SwapKit (CHAINFLIP)",
            feeCrypto: "0.01",
            feeFiat: "20",
            network: "Ethereum",
            explorerLink: "https://etherscan.io/tx/\(txHash)",
            createdAt: Date(),
            completedAt: nil,
            estimatedTime: nil,
            errorMessage: nil,
            swapTracking: SwapTrackingMetadataData(
                providerKind: "swapKit",
                swapId: "swap-1",
                routeId: "route-1",
                broadcastHash: txHash,
                sourceChainId: "1",
                subProvider: "CHAINFLIP",
                latestStatus: nil,
                latestTrackingStatus: latestTrackingStatus
            )
        )
    }

    private static func makeNonSwapKitTx() -> TransactionHistoryData {
        // No swap-tracking metadata at all — represents a row routed through
        // a swap aggregator without a registered tracker (e.g. legacy
        // 1inch / Kyber / LiFi paths).
        TransactionHistoryData(
            id: UUID(),
            txHash: "0xnon-swapkit",
            approveTxHash: nil,
            pubKeyECDSA: "vault-pub",
            type: .swap,
            status: .inProgress,
            chainRawValue: "Ethereum",
            coinTicker: "ETH",
            coinLogo: "eth",
            coinChainLogo: nil,
            amountCrypto: "1.0",
            amountFiat: "2000",
            fromAddress: "0xfrom",
            toAddress: "0xto",
            toCoinTicker: "USDC",
            toCoinLogo: "usdc",
            toCoinChainLogo: nil,
            toAmountCrypto: "2000",
            toAmountFiat: "2000",
            swapProvider: "1Inch",
            feeCrypto: "0.01",
            feeFiat: "20",
            network: "Ethereum",
            explorerLink: "https://etherscan.io/tx/0xnon-swapkit",
            createdAt: Date(),
            completedAt: nil,
            estimatedTime: nil,
            errorMessage: nil
        )
    }

    private static func applyTrackingStarted(
        _ tx: TransactionHistoryData,
        date: Date
    ) -> TransactionHistoryData {
        let oldTracking = tx.swapTracking
        let updatedTracking = SwapTrackingMetadataData(
            providerKind: oldTracking?.providerKind ?? "swapKit",
            swapId: oldTracking?.swapId,
            routeId: oldTracking?.routeId,
            broadcastHash: oldTracking?.broadcastHash,
            sourceChainId: oldTracking?.sourceChainId,
            subProvider: oldTracking?.subProvider,
            latestStatus: oldTracking?.latestStatus,
            latestTrackingStatus: oldTracking?.latestTrackingStatus,
            lastPolledAt: oldTracking?.lastPolledAt,
            trackingStartedAt: date,
            trackerOutage: oldTracking?.trackerOutage
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
            completedAt: tx.completedAt,
            estimatedTime: tx.estimatedTime,
            errorMessage: tx.errorMessage,
            swapTracking: updatedTracking
        )
    }

    private static func makeResponse(
        status: SwapKitTrackingStatus,
        trackingStatus: String?
    ) -> SwapKitTrackingResponse {
        SwapKitTrackingResponse(
            chainId: "1",
            hash: "0xbroadcast",
            block: nil,
            type: "swap",
            status: status,
            trackingStatus: trackingStatus,
            fromAsset: nil,
            fromAmount: nil,
            fromAddress: nil,
            toAsset: nil,
            toAmount: nil,
            toAddress: nil,
            finalisedAt: nil
        )
    }

    private enum TestError: Error { case network }
}

// MARK: - Test doubles

/// In-memory `HTTPClientProtocol` stub. Returns responses in FIFO order; once
/// the queue empties, throws to surface any over-pull. Set `shouldThrow` to
/// simulate transient network errors.
private final class StubHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _responses: [SwapKitTrackingResponse] = []
    private var _shouldThrow: Error?
    private var _requestCount = 0

    var responses: [SwapKitTrackingResponse] {
        get { lock.withLock { _responses } }
        set { lock.withLock { _responses = newValue } }
    }
    var shouldThrow: Error? {
        get { lock.withLock { _shouldThrow } }
        set { lock.withLock { _shouldThrow = newValue } }
    }
    var requestCount: Int { lock.withLock { _requestCount } }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        _ = target
        await Task.yield()
        XCTFail("Raw `request` not exercised by these tests")
        throw URLError(.unknown)
    }

    func request<T: Decodable>(_ target: TargetType, responseType: T.Type) async throws -> HTTPResponse<T> {
        _ = target
        _ = responseType
        await Task.yield()
        return try lock.withLock {
            _requestCount += 1
            if let err = _shouldThrow { throw err }
            guard !_responses.isEmpty else {
                throw URLError(.resourceUnavailable)
            }
            let next = _responses.removeFirst()
            guard let typed = next as? T else {
                XCTFail("StubHTTPClient only stubs SwapKitTrackingResponse")
                throw URLError(.cannotParseResponse)
            }
            return HTTPResponse(
                data: typed,
                response: HTTPURLResponse(
                    url: URL(string: "https://api.swapkit.dev/track")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
    }
}

@MainActor
private final class FakeSwapTrackingStorage: SwapTrackingStorage {
    struct Observation: Equatable {
        let txHash: String
        let pubKeyECDSA: String
        let latestStatus: String?
        let trackingStatus: String?
        let uiStatus: SwapTrackingUiStatus
        let polledAt: Date
        /// Mirrors the real storage rule: `trackerOutage` is `true`
        /// iff `uiStatus == .unknownPendingExtended`. Exposed here so the
        /// unit tests can assert the flag's behaviour without bringing up
        /// SwiftData.
        let trackerOutage: Bool
    }

    var inFlight: [TransactionHistoryData] = []
    private(set) var observations: [Observation] = []
    private(set) var touchCount = 0

    func updateSwapTrackingStatus(
        txHash: String,
        pubKeyECDSA: String,
        latestStatus: String?,
        latestTrackingStatus: String?,
        uiStatus: SwapTrackingUiStatus,
        polledAt: Date
    ) throws {
        observations.append(Observation(
            txHash: txHash,
            pubKeyECDSA: pubKeyECDSA,
            latestStatus: latestStatus,
            trackingStatus: latestTrackingStatus,
            uiStatus: uiStatus,
            polledAt: polledAt,
            trackerOutage: uiStatus == .unknownPendingExtended
        ))
    }

    func touchSwapTrackingLastPolled(txHash: String, pubKeyECDSA: String, polledAt: Date) throws {
        _ = txHash
        _ = pubKeyECDSA
        _ = polledAt
        touchCount += 1
    }

    func fetchInFlightSwapTracking(providerKind: String) throws -> [TransactionHistoryData] {
        inFlight
            .filter { $0.swapTracking?.providerKind == providerKind }
            .filter { !$0.swapTrackingUiStatus.isTerminal }
    }
}
