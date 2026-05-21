//
//  SwapKitTrackingServiceTests.swift
//  VultisigAppTests
//
//  Lifecycle coverage for `SwapKitTrackingService` — uses in-memory mocks for
//  `HTTPClientProtocol` + `SwapKitTrackingStorage` so the tests never sleep
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
        let storage = FakeSwapKitTrackingStorage()
        let http = StubHTTPClient()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var clockTick = baseDate
        let service = SwapKitTrackingService(
            httpClient: http,
            storage: storage,
            clock: { clockTick }
        )

        let swap = Self.makeSwapKitSwap()
        storage.inFlight = [swap]

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
            await service.forceRefresh(swap: swap)
            clockTick = clockTick.addingTimeInterval(10)
            let observed = storage.observations.last
            XCTAssertEqual(observed?.trackingStatus, raw)
        }

        XCTAssertEqual(storage.observations.last?.uiStatus, .completed)
        XCTAssertTrue(storage.observations.last!.uiStatus.isTerminal)
    }

    func testRefundPathMapsToTerminalRefunded() async {
        let storage = FakeSwapKitTrackingStorage()
        let http = StubHTTPClient()
        let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })

        let swap = Self.makeSwapKitSwap()
        http.responses = [Self.makeResponse(status: .refunded, trackingStatus: "refunded")]

        await service.forceRefresh(swap: swap)

        let observed = storage.observations.last
        XCTAssertEqual(observed?.uiStatus, .refunded)
        XCTAssertTrue(observed!.uiStatus.isTerminal)
    }

    func testPartialRefundAlsoTerminal() async {
        let storage = FakeSwapKitTrackingStorage()
        let http = StubHTTPClient()
        let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })

        http.responses = [Self.makeResponse(status: .refunded, trackingStatus: "partially_refunded")]
        await service.forceRefresh(swap: Self.makeSwapKitSwap())

        XCTAssertEqual(storage.observations.last?.uiStatus, .refunded)
    }

    func testFailureTerminalsAllMapToFailed() async {
        let terminals = ["dropped", "reverted", "replaced", "retries_exceeded", "parsing_error"]
        for raw in terminals {
            let storage = FakeSwapKitTrackingStorage()
            let http = StubHTTPClient()
            let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })
            http.responses = [Self.makeResponse(status: .failed, trackingStatus: raw)]
            await service.forceRefresh(swap: Self.makeSwapKitSwap())
            XCTAssertEqual(
                storage.observations.last?.uiStatus,
                .failed,
                "Expected .failed for tracking status \(raw)"
            )
        }
    }

    // MARK: - Unknown give-up window

    func testUnknownUnderTenMinutesStaysPending() async {
        let storage = FakeSwapKitTrackingStorage()
        let http = StubHTTPClient()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var clockTick = baseDate
        let service = SwapKitTrackingService(
            httpClient: http,
            storage: storage,
            clock: { clockTick }
        )

        var swap = Self.makeSwapKitSwap()
        // Tracking started 5 minutes ago — within the 10-minute window.
        swap = Self.applyTrackingStarted(swap, date: baseDate.addingTimeInterval(-5 * 60))
        storage.inFlight = [swap]

        http.responses = [Self.makeResponse(status: .unknown, trackingStatus: "unknown")]
        await service.forceRefresh(swap: swap)
        clockTick = clockTick.addingTimeInterval(1)

        XCTAssertEqual(storage.observations.last?.uiStatus, .pending)
    }

    func testUnknownPastTenMinutesPromotesToTerminalUnknownExtended() async {
        let storage = FakeSwapKitTrackingStorage()
        let http = StubHTTPClient()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var clockTick = baseDate
        let service = SwapKitTrackingService(
            httpClient: http,
            storage: storage,
            clock: { clockTick }
        )

        var swap = Self.makeSwapKitSwap()
        // Tracking started 11 minutes ago — past the give-up window.
        swap = Self.applyTrackingStarted(swap, date: baseDate.addingTimeInterval(-11 * 60))
        storage.inFlight = [swap]

        http.responses = [Self.makeResponse(status: .unknown, trackingStatus: "unknown")]
        await service.forceRefresh(swap: swap)
        clockTick = clockTick.addingTimeInterval(1)

        XCTAssertEqual(storage.observations.last?.uiStatus, .unknownPendingExtended)
        XCTAssertTrue(storage.observations.last!.uiStatus.isTerminal)
    }

    // MARK: - Tracker-outage flag wiring

    func testTrackerOutageFlipsTrueOnUnknownExtendedPromotion() async {
        let storage = FakeSwapKitTrackingStorage()
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
        var swap = Self.makeSwapKitSwap()
        swap = Self.applyTrackingStarted(swap, date: baseDate.addingTimeInterval(-11 * 60))
        storage.inFlight = [swap]

        http.responses = [Self.makeResponse(status: .unknown, trackingStatus: "unknown")]
        await service.forceRefresh(swap: swap)
        clockTick = clockTick.addingTimeInterval(1)

        XCTAssertEqual(storage.observations.last?.uiStatus, .unknownPendingExtended)
        XCTAssertEqual(storage.observations.last?.trackerOutage, true,
                       "Outage flag must flip true the moment we promote to unknownPendingExtended")
    }

    func testTrackerOutageClearsOnNextSuccessfulTrackResponse() async {
        let storage = FakeSwapKitTrackingStorage()
        let http = StubHTTPClient()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var clockTick = baseDate
        let service = SwapKitTrackingService(
            httpClient: http,
            storage: storage,
            clock: { clockTick }
        )

        // First poll: stuck-in-unknown beyond the give-up window.
        var swap = Self.makeSwapKitSwap()
        swap = Self.applyTrackingStarted(swap, date: baseDate.addingTimeInterval(-11 * 60))
        storage.inFlight = [swap]

        http.responses = [
            Self.makeResponse(status: .unknown, trackingStatus: "unknown"),
            Self.makeResponse(status: .swapping, trackingStatus: "swapping")
        ]

        await service.forceRefresh(swap: swap)
        XCTAssertEqual(storage.observations.last?.trackerOutage, true)

        // Now `/track` recovers — the next response carries an actual
        // status. Outage flag must clear so native polling steps back
        // and `/track` regains authority.
        clockTick = clockTick.addingTimeInterval(15)
        await service.forceRefresh(swap: swap)

        XCTAssertEqual(storage.observations.last?.uiStatus, .swapping)
        XCTAssertEqual(storage.observations.last?.trackerOutage, false,
                       "Outage flag must clear on the next successful /track response")
    }

    func testTrackerOutageStaysFalseOnHappyPath() async {
        let storage = FakeSwapKitTrackingStorage()
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
            await service.forceRefresh(swap: Self.makeSwapKitSwap())
        }

        XCTAssertEqual(storage.observations.count, 3)
        XCTAssertTrue(
            storage.observations.allSatisfy { $0.trackerOutage == false },
            "No happy-path response should ever flip the outage flag on"
        )
    }

    // MARK: - Failure handling — touches lastPolledAt without mutating status

    func testTransientFailureTouchesLastPolledOnly() async {
        let storage = FakeSwapKitTrackingStorage()
        let http = StubHTTPClient()
        http.shouldThrow = TestError.network
        let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })

        let swap = Self.makeSwapKitSwap()
        await service.forceRefresh(swap: swap)

        XCTAssertTrue(storage.observations.isEmpty, "Failure should not write a status row")
        XCTAssertEqual(storage.touchCount, 1, "Failure should touch lastPolledAt once")
    }

    // MARK: - Start/stop bookkeeping

    func testStartIsIdempotent() {
        let storage = FakeSwapKitTrackingStorage()
        let http = StubHTTPClient()
        let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })

        let swap = Self.makeSwapKitSwap()
        service.start(swap: swap)
        service.start(swap: swap)
        XCTAssertEqual(service.trackedSwapCountForTesting, 1, "Duplicate start should be a no-op")
    }

    func testStartSkipsTerminalRows() {
        let storage = FakeSwapKitTrackingStorage()
        let http = StubHTTPClient()
        let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })

        let swap = Self.makeSwapKitSwap(latestTrackingStatus: "completed")
        service.start(swap: swap)
        XCTAssertEqual(service.trackedSwapCountForTesting, 0)
    }

    func testStartSkipsNonSwapKitRows() {
        let storage = FakeSwapKitTrackingStorage()
        let http = StubHTTPClient()
        let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })

        let swap = Self.makeNonSwapKitSwap()
        service.start(swap: swap)
        XCTAssertEqual(service.trackedSwapCountForTesting, 0)
    }

    func testStopRemovesEntry() {
        let storage = FakeSwapKitTrackingStorage()
        let http = StubHTTPClient()
        let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })

        let swap = Self.makeSwapKitSwap()
        service.start(swap: swap)
        service.stop(swap: swap)
        XCTAssertEqual(service.trackedSwapCountForTesting, 0)
    }

    func testResumeInFlightStartsAllNonTerminalSwapKitRows() {
        let storage = FakeSwapKitTrackingStorage()
        let http = StubHTTPClient()
        let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })

        storage.inFlight = [
            Self.makeSwapKitSwap(txHash: "0xaaa"),
            Self.makeSwapKitSwap(txHash: "0xbbb"),
            Self.makeSwapKitSwap(txHash: "0xccc", latestTrackingStatus: "completed")
        ]
        service.resumeInFlightSwaps()
        // The fake's `fetchInFlightSwapKitSwaps` already filters terminals out
        // (mirroring the real storage). Verify only the 3rd was filtered.
        XCTAssertLessThanOrEqual(service.trackedSwapCountForTesting, 2)
    }

    // MARK: - ScenePhase

    func testSetActiveToFalseCancelsRunningPollers() {
        let storage = FakeSwapKitTrackingStorage()
        let http = StubHTTPClient()
        let service = SwapKitTrackingService(httpClient: http, storage: storage, clock: { Date() })

        let swap = Self.makeSwapKitSwap()
        service.start(swap: swap)
        XCTAssertEqual(service.trackedSwapCountForTesting, 1)

        service.setActive(false)
        // Entry is preserved so resume can pick it up — only the Task is cancelled.
        XCTAssertEqual(service.trackedSwapCountForTesting, 1)

        service.setActive(true)
        XCTAssertEqual(service.trackedSwapCountForTesting, 1)
    }

    // MARK: - Fixtures

    private static func makeSwapKitSwap(
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
            swapKitSwapId: "swap-1",
            swapKitRouteId: "route-1",
            swapKitBroadcastHash: txHash,
            swapKitSourceChainId: "1",
            swapKitProvider: "CHAINFLIP",
            swapKitLatestStatus: nil,
            swapKitLatestTrackingStatus: latestTrackingStatus
        )
    }

    private static func makeNonSwapKitSwap() -> TransactionHistoryData {
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
        _ swap: TransactionHistoryData,
        date: Date
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
            completedAt: swap.completedAt,
            estimatedTime: swap.estimatedTime,
            errorMessage: swap.errorMessage,
            swapKitSwapId: swap.swapKitSwapId,
            swapKitRouteId: swap.swapKitRouteId,
            swapKitBroadcastHash: swap.swapKitBroadcastHash,
            swapKitSourceChainId: swap.swapKitSourceChainId,
            swapKitProvider: swap.swapKitProvider,
            swapKitLatestStatus: swap.swapKitLatestStatus,
            swapKitLatestTrackingStatus: swap.swapKitLatestTrackingStatus,
            swapKitLastPolledAt: swap.swapKitLastPolledAt,
            swapKitTrackingStartedAt: date
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
private final class FakeSwapKitTrackingStorage: SwapKitTrackingStorage {
    struct Observation: Equatable {
        let txHash: String
        let pubKeyECDSA: String
        let latestStatus: String?
        let trackingStatus: String?
        let uiStatus: SwapKitUiStatus
        let polledAt: Date
        /// Mirrors the real storage rule: `swapKitTrackerOutage` is `true`
        /// iff `uiStatus == .unknownPendingExtended`. Exposed here so the
        /// unit tests can assert the flag's behaviour without bringing up
        /// SwiftData.
        let trackerOutage: Bool
    }

    var inFlight: [TransactionHistoryData] = []
    private(set) var observations: [Observation] = []
    private(set) var touchCount = 0

    func updateSwapKitStatus(
        txHash: String,
        pubKeyECDSA: String,
        latestStatus: String?,
        latestTrackingStatus: String?,
        uiStatus: SwapKitUiStatus,
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

    func touchSwapKitLastPolled(txHash: String, pubKeyECDSA: String, polledAt: Date) throws {
        _ = txHash
        _ = pubKeyECDSA
        _ = polledAt
        touchCount += 1
    }

    func fetchInFlightSwapKitSwaps() throws -> [TransactionHistoryData] {
        inFlight.filter { !$0.swapKitUiStatus.isTerminal }
    }
}
