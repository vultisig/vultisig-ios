//
//  THORChainLimitTrackingPollTests.swift
//  VultisigAppTests
//
//  Drives the limit tracker's state machine through its real transitions with
//  stubbed HTTP + collaborators, one cycle at a time so nothing sleeps.
//
//  The invariant under test throughout: an order is only ever declared terminal
//  on evidence. Every ambiguity — an unparseable queue, a network failure, a
//  response we don't recognise, an outcome Midgard hasn't indexed — must leave
//  it resting, because nothing revisits a terminal order.
//

import XCTest
@testable import VultisigApp

@MainActor
final class THORChainLimitTrackingPollTests: XCTestCase {

    private let sender = "thor1sender"

    // MARK: - Resting

    func testAnOrderStillInTheQueueIsRecordedAsResting() async {
        let env = TestEnv(queueBody: .resting(hash: "ABC123", deposit: "1000", inAmount: "0", outAmount: "0"))
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.orders.observations.last?.status, .pending)
        XCTAssertEqual(env.service.uiStatusByTxHash["ABC123"], .resting)
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 1, "still resting — keep tracking it")
    }

    /// The queue is polled ONCE per sender, not once per order — that's the
    /// whole reason for the list endpoint.
    func testOneRequestCoversEveryOrderForASender() async {
        let env = TestEnv(queueBody: .restingMany(hashes: ["ABC123", "DEF456"]))
        env.service.start(tx: env.makeRow(txHash: "ABC123"))
        env.service.start(tx: env.makeRow(txHash: "DEF456"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.http.requestCount, 1, "two orders, one sender, one request")
        XCTAssertEqual(env.service.uiStatusByTxHash["ABC123"], .resting)
        XCTAssertEqual(env.service.uiStatusByTxHash["DEF456"], .resting)
    }

    func testTheFillSplitIsRecordedFromTheQueue() async {
        let env = TestEnv(queueBody: .resting(hash: "ABC123", deposit: "1000", inAmount: "400", outAmount: "25"))
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        let observation = env.orders.observations.last
        XCTAssertEqual(observation?.depositAmount, "1000")
        XCTAssertEqual(observation?.filledInAmount, "400")
        XCTAssertEqual(observation?.filledOutAmount, "25")
    }

    /// A partially-filled order is still resting — the remainder is genuinely
    /// still working.
    func testAPartiallyFilledOrderStaysResting() async {
        let env = TestEnv(queueBody: .resting(hash: "ABC123", deposit: "1000", inAmount: "400", outAmount: "25"))
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.service.uiStatusByTxHash["ABC123"], .resting)
        XCTAssertFalse(env.service.uiStatusByTxHash["ABC123"]!.isTerminal)
    }

    /// The queue's hash casing needn't match what we broadcast under; hex case
    /// carries no meaning and must not make an order look closed.
    func testHashMatchingIsCaseInsensitive() async {
        let env = TestEnv(queueBody: .resting(hash: "abc123", deposit: "1000", inAmount: "0", outAmount: "0"))
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.service.uiStatusByTxHash["ABC123"], .resting)
        XCTAssertEqual(env.outcomes.resolveCount, 0, "must not be treated as closed")
    }

    /// A poll is scoped to ONE sender's queue, so it must not reason about
    /// another address's orders — their absence from this response says nothing
    /// about them. (`start` seeds a UI status for any row it takes up; what must
    /// not happen is an observation or an outcome lookup.)
    func testAPollDoesNotReasonAboutAnotherSendersOrders() async {
        let env = TestEnv(queueBody: .empty)
        env.service.start(tx: env.makeRow(txHash: "OTHER1", fromAddress: "thor1elsewhere"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertTrue(env.orders.observations.isEmpty, "another sender's order must not be written")
        XCTAssertEqual(env.outcomes.resolveCount, 0, "absence from this sender's queue proves nothing about it")
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 1, "and it must stay tracked")
    }

    // MARK: - Disappearance → terminal, on evidence

    func testAnOrderThatLeavesTheQueueAndFilledIsCompleted() async {
        let env = TestEnv(queueBody: .empty, outcome: .filled)
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.orders.observations.last?.status, .filled)
        XCTAssertEqual(env.service.uiStatusByTxHash["ABC123"], .completed)
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 0, "terminal — stop tracking")
    }

    /// Recorded as REFUNDED, not expired. The funds coming back is what we
    /// observed; "your order expired" is a cause we can't corroborate, and it
    /// would be a fabricated explanation for an order rejected at placement.
    func testAnOrderThatLeavesTheQueueAndRefundedIsRecordedAsRefunded() async {
        let env = TestEnv(queueBody: .empty, outcome: .refunded)
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.orders.observations.last?.status, .refunded)
        XCTAssertEqual(env.service.uiStatusByTxHash["ABC123"], .refunded)
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 0)
    }

    /// Terminal writes carry no amounts, so the last resting observation — the
    /// final word on how much filled — survives the order leaving the queue.
    func testATerminalWriteDoesNotOverwriteTheLastKnownSplit() async {
        let env = TestEnv(queueBody: .resting(hash: "ABC123", deposit: "1000", inAmount: "400", outAmount: "25"))
        env.service.start(tx: env.makeRow(txHash: "ABC123"))
        await env.service.pollOnceForTesting(sender: sender)

        env.http.body = QueueBody.empty.json
        env.outcomes.outcome = .refunded
        await env.service.pollOnceForTesting(sender: sender)

        let terminal = env.orders.observations.last
        XCTAssertEqual(terminal?.status, .refunded)
        XCTAssertNil(terminal?.depositAmount, "nil leaves the stored split alone")
        XCTAssertNil(terminal?.filledInAmount)
        XCTAssertNil(terminal?.filledOutAmount)
    }

    // MARK: - Ambiguity must never close an order

    /// Gone from the queue but Midgard hasn't indexed it yet: we know it closed
    /// but not how. Guessing would be permanent.
    func testAnUnresolvableOutcomeLeavesTheOrderRestingAndTracked() async {
        let env = TestEnv(queueBody: .empty, outcome: .unresolved)
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertNotEqual(env.orders.observations.last?.status, .refunded)
        XCTAssertNotEqual(env.orders.observations.last?.status, .filled)
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 1, "keep asking until it answers")
    }

    /// An unresolved order resolves on a later poll, once indexing catches up.
    func testAnUnresolvedOrderIsResolvedOnALaterPoll() async {
        let env = TestEnv(queueBody: .empty, outcome: .unresolved)
        env.service.start(tx: env.makeRow(txHash: "ABC123"))
        await env.service.pollOnceForTesting(sender: sender)
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 1)

        env.outcomes.outcome = .filled
        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.service.uiStatusByTxHash["ABC123"], .completed)
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 0)
    }

    /// The `limit_swaps` key absent is a response we don't understand — NOT an
    /// empty queue. Reading it as empty would close every order at once.
    func testAnUnrecognisedQueueEnvelopeDoesNotCloseOrders() async {
        let env = TestEnv(queueBody: .unrecognisedEnvelope, outcome: .refunded)
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.outcomes.resolveCount, 0, "must not even ask — we don't know it closed")
        XCTAssertTrue(env.orders.observations.isEmpty)
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 1)
    }

    func testANetworkFailureDoesNotCloseOrders() async {
        let env = TestEnv(queueBody: .empty, outcome: .refunded)
        env.http.shouldThrow = true
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.outcomes.resolveCount, 0)
        XCTAssertTrue(env.orders.observations.isEmpty)
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 1)
    }

    /// The tracker must never write `unknownPendingExtended`: that flag hands
    /// authority back to the native poller, which would confirm the deposit and
    /// report a resting order Successful — the original bug.
    func testTheTrackerNeverSurrendersToNativePolling() async {
        let env = TestEnv(queueBody: .empty, outcome: .refunded)
        env.http.shouldThrow = true
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)
        await env.service.pollOnceForTesting(sender: sender)
        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertFalse(
            env.storage.observedUiStatuses.contains(.unknownPendingExtended),
            "an outage must never hand a limit row back to native polling"
        )
    }

    /// If the authoritative write fails, the order must stay tracked. Releasing
    /// it would leave `LimitOrder` permanently non-terminal with nothing left to
    /// correct it, while the row had already moved on — the two tables
    /// disagreeing forever.
    func testAnOrderIsNotReleasedWhenTheAuthoritativeWriteFails() async {
        let env = TestEnv(queueBody: .empty, outcome: .filled)
        env.orders.shouldThrow = true
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.service.trackedOrderCountForTesting, 1, "keep it, so a later poll can retry the write")
    }

    /// An observer that can't resolve the vault must FAIL, not return quietly.
    /// Returning normally would report success for a write that never happened,
    /// and the order would be released with `LimitOrder` never updated.
    func testAVaultThatCannotBeResolvedFailsTheWriteRatherThanReleasing() async {
        let env = TestEnv(queueBody: .empty, outcome: .filled)
        env.orders.error = LimitOrderObservingError.vaultUnavailable(pubKeyECDSA: "vault-pub")
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.service.trackedOrderCountForTesting, 1)
    }

    /// A later poll completes the write that previously failed.
    func testAFailedTerminalWriteIsRetriedOnALaterPoll() async {
        let env = TestEnv(queueBody: .empty, outcome: .filled)
        env.orders.shouldThrow = true
        env.service.start(tx: env.makeRow(txHash: "ABC123"))
        await env.service.pollOnceForTesting(sender: sender)

        env.orders.shouldThrow = false
        await env.service.pollOnceForTesting(sender: sender)

        XCTAssertEqual(env.orders.observations.last?.status, .filled)
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 0)
    }

    // MARK: - Tracking preconditions

    /// Without a sender the queue can't be scoped, and an unscoped request
    /// returns the whole network's queue.
    func testARowWithoutASenderIsNotTracked() {
        // Scheduled, so the "no poll started" assertion is meaningful rather
        // than trivially true.
        let env = TestEnv(queueBody: .empty, scheduled: true)

        env.service.start(tx: env.makeRow(txHash: "ABC123", fromAddress: ""))

        XCTAssertEqual(env.service.trackedOrderCountForTesting, 0)
        XCTAssertEqual(env.service.activeSenderPollCountForTesting, 0)
    }

    func testStoppingTheLastOrderForASenderEndsItsPoll() {
        let env = TestEnv(queueBody: .empty, scheduled: true)
        env.service.start(tx: env.makeRow(txHash: "ABC123"))
        XCTAssertEqual(env.service.activeSenderPollCountForTesting, 1)

        env.service.stop(txHash: "ABC123")

        XCTAssertEqual(env.service.activeSenderPollCountForTesting, 0)
    }

    /// Two orders from the same address share ONE poll loop — the queue is
    /// scoped per sender, which is the whole reason for the list endpoint.
    func testOrdersFromOneSenderShareASinglePollLoop() {
        let env = TestEnv(queueBody: .empty, scheduled: true)

        env.service.start(tx: env.makeRow(txHash: "ABC123"))
        env.service.start(tx: env.makeRow(txHash: "DEF456"))

        XCTAssertEqual(env.service.trackedOrderCountForTesting, 2)
        XCTAssertEqual(env.service.activeSenderPollCountForTesting, 1)
    }

    func testBackgroundingCancelsPollsAndForegroundingResumesThem() {
        let env = TestEnv(queueBody: .empty, scheduled: true)
        env.service.start(tx: env.makeRow(txHash: "ABC123"))

        env.service.setActive(false)
        XCTAssertEqual(env.service.activeSenderPollCountForTesting, 0)
        XCTAssertEqual(env.service.trackedOrderCountForTesting, 1, "still tracked, just not polling")

        env.service.setActive(true)
        XCTAssertEqual(env.service.activeSenderPollCountForTesting, 1)
    }
}

// MARK: - Test environment

@MainActor
private struct TestEnv {
    let http: StubQueueHTTPClient
    let storage: RecordingTrackingStorage
    let orders: RecordingLimitOrderObserver
    let outcomes: StubOutcomeResolver
    let service: THORChainLimitTrackingService

    /// - Parameter scheduled: leave `false` (the default) to suppress the
    ///   background poll loop `start` would otherwise kick off, so each test
    ///   drives cycles itself via `pollOnceForTesting` and asserts on exactly
    ///   the requests it caused. Pass `true` only to exercise scheduling.
    init(queueBody: QueueBody, outcome: LimitOrderOutcome = .unresolved, scheduled: Bool = false) {
        http = StubQueueHTTPClient(body: queueBody.json)
        storage = RecordingTrackingStorage()
        orders = RecordingLimitOrderObserver()
        outcomes = StubOutcomeResolver(outcome: outcome)
        service = THORChainLimitTrackingService(
            httpClient: http,
            storage: storage,
            orders: orders,
            outcomes: outcomes
        )
        if !scheduled {
            service.setActive(false)
        }
    }

    func makeRow(txHash: String, fromAddress: String = "thor1sender") -> TransactionHistoryData {
        TransactionHistoryData(
            id: UUID(),
            txHash: txHash,
            approveTxHash: nil,
            pubKeyECDSA: "vault-pub",
            type: .swap,
            status: .inProgress,
            chainRawValue: Chain.thorChain.rawValue,
            coinTicker: "RUNE",
            coinLogo: "rune",
            coinChainLogo: nil,
            amountCrypto: "600.12",
            amountFiat: "1000",
            fromAddress: fromAddress,
            toAddress: "bc1qto",
            toCoinTicker: "BTC",
            toCoinLogo: "btc",
            toCoinChainLogo: nil,
            toAmountCrypto: "0.0125",
            toAmountFiat: "1000",
            swapProvider: "THORChain",
            feeCrypto: "0.02",
            feeFiat: "0.04",
            network: "THORChain",
            explorerLink: "https://runescan.io/tx/\(txHash)",
            createdAt: Date(),
            completedAt: nil,
            estimatedTime: nil,
            errorMessage: nil,
            swapTracking: THORChainLimitTrackingService.metadata(
                broadcastHash: txHash,
                sourceChain: .thorChain
            )
        )
    }
}

private enum QueueBody {
    case empty
    case resting(hash: String, deposit: String, inAmount: String, outAmount: String)
    case restingMany(hashes: [String])
    /// A 200 whose `limit_swaps` key is absent.
    case unrecognisedEnvelope

    var json: String {
        switch self {
        case .empty:
            return #"{"limit_swaps":[]}"#
        case let .resting(hash, deposit, inAmount, outAmount):
            return """
            {"limit_swaps":[{"time_to_expiry_blocks":"39069",
              "swap":{"tx":{"id":"\(hash)","from_address":"thor1sender"},
                      "state":{"deposit":"\(deposit)","in":"\(inAmount)","out":"\(outAmount)","failed_swap_reasons":[]}}}]}
            """
        case let .restingMany(hashes):
            let entries = hashes.map {
                """
                {"swap":{"tx":{"id":"\($0)"},"state":{"deposit":"1000","in":"0","out":"0"}}}
                """
            }.joined(separator: ",")
            return #"{"limit_swaps":[\#(entries)]}"#
        case .unrecognisedEnvelope:
            return #"{"some_other_envelope":"we have never seen this"}"#
        }
    }
}

// MARK: - Fakes

private final class StubQueueHTTPClient: HTTPClientProtocol {
    var body: String
    var shouldThrow = false
    private(set) var requestCount = 0

    struct StubError: Error {}

    init(body: String) {
        self.body = body
    }

    func request(_: TargetType) async throws -> HTTPResponse<Data> { // swiftlint:disable:this async_without_await
        requestCount += 1
        if shouldThrow { throw StubError() }
        let url = URL(string: "https://example.invalid")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: Data(body.utf8), response: response)
    }

    func requestEmpty(_ target: TargetType) async throws -> HTTPResponse<EmptyResponse> {
        _ = try await request(target)
        let url = URL(string: "https://example.invalid")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: EmptyResponse(), response: response)
    }
}

@MainActor
private final class RecordingLimitOrderObserver: LimitOrderObserving {
    struct Observation {
        let inboundTxHash: String
        let status: LimitOrderStatus
        let depositAmount: String?
        let filledInAmount: String?
        let filledOutAmount: String?
    }

    private(set) var observations: [Observation] = []
    var shouldThrow = false
    /// A specific error to throw, when the test cares which one.
    var error: Error?

    struct WriteError: Error {}

    func recordObservation(
        inboundTxHash: String,
        pubKeyECDSA _: String,
        status: LimitOrderStatus,
        depositAmount: String?,
        filledInAmount: String?,
        filledOutAmount: String?
    ) throws {
        if let error { throw error }
        if shouldThrow { throw WriteError() }
        observations.append(Observation(
            inboundTxHash: inboundTxHash,
            status: status,
            depositAmount: depositAmount,
            filledInAmount: filledInAmount,
            filledOutAmount: filledOutAmount
        ))
    }
}

@MainActor
private final class StubOutcomeResolver: LimitOrderOutcomeResolving {
    var outcome: LimitOrderOutcome
    private(set) var resolveCount = 0

    init(outcome: LimitOrderOutcome) {
        self.outcome = outcome
    }

    func resolveOutcome(inboundTxHash _: String, sourceChain _: Chain) async -> LimitOrderOutcome { // swiftlint:disable:this async_without_await
        resolveCount += 1
        return outcome
    }
}

@MainActor
private final class RecordingTrackingStorage: SwapTrackingStorage {
    private(set) var observedUiStatuses: [SwapTrackingUiStatus] = []
    var inFlight: [TransactionHistoryData] = []

    func updateSwapTrackingStatus(
        txHash _: String,
        pubKeyECDSA _: String,
        latestStatus _: String?,
        latestTrackingStatus _: String?,
        uiStatus: SwapTrackingUiStatus,
        polledAt _: Date
    ) throws {
        observedUiStatuses.append(uiStatus)
    }

    func touchSwapTrackingLastPolled(txHash _: String, pubKeyECDSA _: String, polledAt _: Date) throws {}

    func fetchInFlightSwapTracking(providerKind _: String) throws -> [TransactionHistoryData] { inFlight }
}
