//
//  RippleRetryTests.swift
//  VultisigAppTests
//
//  Pins the bounded same-host retry for transient XRPL node errors. The default
//  XRPL host (xrplcluster.com) is a load-balanced pool; some backends run stale
//  rippled and answer `amendmentBlocked` (HTTP 200 with `result.error`). A
//  same-host retry routes to a different, healthy backend — so the fix retries
//  the same host and deliberately adds no fallback host list. These tests use an
//  injected no-op clock (no real sleeps) and a sequenced HTTP stub.
//

@testable import VultisigApp
import XCTest

final class RippleRetryTests: XCTestCase {

    // MARK: - Policy: JSON-RPC body errors

    func testAmendmentBlockedIsRetryable() {
        XCTAssertTrue(RippleRetryPolicy.isRetryable(rpcError: "amendmentBlocked"))
    }

    func testNodeUnavailableFamilyIsRetryable() {
        // Includes the Clio forwarding failure (submit/server_state are forwarded).
        for code in ["noNetwork", "noCurrent", "noClosed", "failedToForward"] {
            XCTAssertTrue(RippleRetryPolicy.isRetryable(rpcError: code), "\(code) should be retryable")
        }
    }

    func testBusyAndSlowDownAreRetryable() {
        // Per-backend overload signals; a pool retry lands on a different node.
        XCTAssertTrue(RippleRetryPolicy.isRetryable(rpcError: "tooBusy"))
        XCTAssertTrue(RippleRetryPolicy.isRetryable(rpcError: "slowDown"))
    }

    func testBusinessErrorsAreNotRetryable() {
        // These are real outcomes, not transient node faults — never retry them.
        for code in ["actNotFound", "txnNotFound", "invalidParams", "tefALREADY", "tecUNFUNDED_PAYMENT"] {
            XCTAssertFalse(RippleRetryPolicy.isRetryable(rpcError: code), "\(code) should NOT be retryable")
        }
    }

    func testNilRpcErrorIsNotRetryable() {
        XCTAssertFalse(RippleRetryPolicy.isRetryable(rpcError: nil))
    }

    // MARK: - Policy: transport errors

    func testTransientTransportErrorsAreRetryable() {
        XCTAssertTrue(RippleRetryPolicy.isRetryable(transportError: HTTPError.timeout))
        XCTAssertTrue(RippleRetryPolicy.isRetryable(transportError: HTTPError.networkError(HTTPError.noData)))
        XCTAssertTrue(RippleRetryPolicy.isRetryable(transportError: HTTPError.statusCode(503, nil)))
        XCTAssertTrue(RippleRetryPolicy.isRetryable(transportError: HTTPError.statusCode(500, nil)))
    }

    func testClientErrorsAndCancellationAreNotRetryable() {
        XCTAssertFalse(RippleRetryPolicy.isRetryable(transportError: HTTPError.statusCode(404, nil)))
        XCTAssertFalse(RippleRetryPolicy.isRetryable(transportError: HTTPError.statusCode(400, nil)))
        XCTAssertFalse(RippleRetryPolicy.isRetryable(transportError: HTTPError.decodingFailed(HTTPError.noData)))
        XCTAssertFalse(RippleRetryPolicy.isRetryable(transportError: CancellationError()))
    }

    func testWrappedCancellationIsNotRetryable() {
        // Cancellation must never be retried, even wrapped in `.networkError`.
        XCTAssertFalse(RippleRetryPolicy.isRetryable(transportError: HTTPError.networkError(CancellationError())))
        XCTAssertFalse(RippleRetryPolicy.isRetryable(transportError: HTTPError.networkError(URLError(.cancelled))))
        // A genuine transport failure wrapped in `.networkError` still retries.
        XCTAssertTrue(RippleRetryPolicy.isRetryable(transportError: HTTPError.networkError(URLError(.networkConnectionLost))))
    }

    // MARK: - Policy: backoff

    func testBackoffIsPositiveMonotonicAndBounded() {
        let first = RippleRetryPolicy.backoff(forAttempt: 1)
        let second = RippleRetryPolicy.backoff(forAttempt: 2)
        XCTAssertEqual(first, .milliseconds(250))
        XCTAssertEqual(second, .milliseconds(500))
        XCTAssertLessThan(first, second)
        // Bounded: the largest backoff within the retry budget stays sub-second.
        let last = RippleRetryPolicy.backoff(forAttempt: RippleRetryPolicy.maxAttempts - 1)
        XCTAssertLessThanOrEqual(last, .milliseconds(500))
    }

    // MARK: - Retrier: generic behavior

    func testRetryableRpcErrorThenSuccessIsRetried() async throws {
        let stub = SequencedHTTPClient()
        stub.enqueue(FakeRippleResponse(rpcError: "amendmentBlocked", tag: "stale"))
        stub.enqueue(FakeRippleResponse(rpcError: nil, tag: "ok"))
        let sleeper = RecordingSleeper()
        let retrier = RippleRequestRetrier(httpClient: stub, sleep: sleeper.sleep)

        let body = try await retrier.request(AnyTarget(), responseType: FakeRippleResponse.self)

        XCTAssertEqual(body.tag, "ok")
        XCTAssertEqual(stub.callCount, 2, "one initial call + one retry")
        XCTAssertEqual(sleeper.count, 1, "one backoff before the single retry")
        assertSameHost(stub, expected: RippleAPI.defaultHost)
    }

    func testNonRetryableErrorSurfacedWithoutRetry() async throws {
        let stub = SequencedHTTPClient()
        stub.enqueue(FakeRippleResponse(rpcError: "actNotFound", tag: "unfunded"))
        let sleeper = RecordingSleeper()
        let retrier = RippleRequestRetrier(httpClient: stub, sleep: sleeper.sleep)

        let body = try await retrier.request(AnyTarget(), responseType: FakeRippleResponse.self)

        XCTAssertEqual(body.rpcError, "actNotFound", "surfaced unchanged")
        XCTAssertEqual(stub.callCount, 1, "must not retry a business error")
        XCTAssertEqual(sleeper.count, 0)
    }

    func testRetriesExhaustedThrowsLastError() async {
        let stub = SequencedHTTPClient()
        // Distinct retryable errors so the surfaced value can only be the LAST
        // attempted one — not the first or a hard-coded value. A trailing extra
        // is queued to prove the loop stops at the cap and never reaches it.
        stub.enqueue(FakeRippleResponse(rpcError: "noNetwork", tag: "a"))
        stub.enqueue(FakeRippleResponse(rpcError: "tooBusy", tag: "b"))
        stub.enqueue(FakeRippleResponse(rpcError: "amendmentBlocked", tag: "c"))
        stub.enqueue(FakeRippleResponse(rpcError: "slowDown", tag: "unreached"))
        let sleeper = RecordingSleeper()
        let retrier = RippleRequestRetrier(httpClient: stub, sleep: sleeper.sleep)

        do {
            _ = try await retrier.request(AnyTarget(), responseType: FakeRippleResponse.self)
            XCTFail("Expected exhaustion to throw rather than return stale data")
        } catch let error as RippleRetryError {
            guard case .exhausted(let rpcError) = error else {
                return XCTFail("Unexpected RippleRetryError: \(error)")
            }
            XCTAssertEqual(rpcError, "amendmentBlocked", "the LAST attempted error is surfaced")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(stub.callCount, RippleRetryPolicy.maxAttempts, "bounded: 1 try + (maxAttempts - 1) retries")
        XCTAssertEqual(sleeper.count, RippleRetryPolicy.maxAttempts - 1)
        assertSameHost(stub, expected: RippleAPI.defaultHost)
    }

    func testTransientTransportErrorThenSuccessIsRetried() async throws {
        let stub = SequencedHTTPClient()
        stub.enqueueError(HTTPError.timeout)
        stub.enqueue(FakeRippleResponse(rpcError: nil, tag: "ok"))
        let sleeper = RecordingSleeper()
        let retrier = RippleRequestRetrier(httpClient: stub, sleep: sleeper.sleep)

        let body = try await retrier.request(AnyTarget(), responseType: FakeRippleResponse.self)

        XCTAssertEqual(body.tag, "ok")
        XCTAssertEqual(stub.callCount, 2)
        XCTAssertEqual(sleeper.count, 1)
    }

    func testNonRetryableTransportErrorSurfacedWithoutRetry() async {
        let stub = SequencedHTTPClient()
        stub.enqueueError(HTTPError.statusCode(404, nil))
        let sleeper = RecordingSleeper()
        let retrier = RippleRequestRetrier(httpClient: stub, sleep: sleeper.sleep)

        do {
            _ = try await retrier.request(AnyTarget(), responseType: FakeRippleResponse.self)
            XCTFail("Expected the 404 to propagate")
        } catch let error as HTTPError {
            if case .statusCode(let code, _) = error {
                XCTAssertEqual(code, 404)
            } else {
                XCTFail("Unexpected HTTPError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(stub.callCount, 1)
        XCTAssertEqual(sleeper.count, 0)
    }

    func testCancellationIsNotRetried() async {
        let stub = SequencedHTTPClient()
        stub.enqueueError(CancellationError())
        let sleeper = RecordingSleeper()
        let retrier = RippleRequestRetrier(httpClient: stub, sleep: sleeper.sleep)

        do {
            _ = try await retrier.request(AnyTarget(), responseType: FakeRippleResponse.self)
            XCTFail("Expected the cancellation to propagate")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(stub.callCount, 1, "cancellation must never be retried")
    }

    // MARK: - Broadcast idempotency (real RippleSubmitResponse)

    func testBroadcastRetriesAmendmentBlockedThenReturnsHash() async throws {
        let stub = SequencedHTTPClient()
        stub.enqueue(Self.decode(RippleSubmitResponse.self, Self.amendmentBlockedBody))
        stub.enqueue(Self.decode(RippleSubmitResponse.self, Self.submitSuccessBody))
        let sleeper = RecordingSleeper()
        let service = RippleService(resolver: NoOverrideResolver(), httpClient: stub, sleep: sleeper.sleep)

        let hash = try await service.broadcastTransaction("DEADBEEF")

        XCTAssertEqual(hash, "ABC123")
        XCTAssertEqual(stub.callCount, 2, "one blocked submit + one healthy submit — no duplicate submit")
        assertSameHost(stub, expected: RippleAPI.defaultHost)
    }

    func testBroadcastExhaustedIsBoundedAndThrows() async {
        let stub = SequencedHTTPClient()
        for _ in 0..<10 { stub.enqueue(Self.decode(RippleSubmitResponse.self, Self.amendmentBlockedBody)) }
        let sleeper = RecordingSleeper()
        let service = RippleService(resolver: NoOverrideResolver(), httpClient: stub, sleep: sleeper.sleep)

        do {
            _ = try await service.broadcastTransaction("DEADBEEF")
            XCTFail("Expected broadcast to surface the node error after the cap")
        } catch let error as RippleRetryError {
            guard case .exhausted(let rpcError) = error else {
                return XCTFail("Unexpected RippleRetryError: \(error)")
            }
            XCTAssertEqual(rpcError, "amendmentBlocked")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(stub.callCount, RippleRetryPolicy.maxAttempts, "broadcast must not submit beyond the retry bound")
    }

    // MARK: - Read paths (server_state / account_info)

    func testFetchServerStateRetriesAmendmentBlockedThenSucceeds() async throws {
        let stub = SequencedHTTPClient()
        stub.enqueue(Self.decode(RippleServerStateResponse.self, Self.amendmentBlockedBody))
        stub.enqueue(Self.decode(RippleServerStateResponse.self, Self.serverStateBody))
        let sleeper = RecordingSleeper()
        let service = RippleService(resolver: NoOverrideResolver(), httpClient: stub, sleep: sleeper.sleep)

        let state = try await service.fetchServerState()

        XCTAssertEqual(state?.result?.state?.validatedLedger?.baseFee, 10)
        XCTAssertEqual(stub.callCount, 2)
        assertSameHost(stub, expected: RippleAPI.defaultHost)
    }

    func testFetchAccountsInfoRetriesAmendmentBlockedThenSucceeds() async throws {
        let stub = SequencedHTTPClient()
        stub.enqueue(Self.decode(RippleAccountResponse.self, Self.amendmentBlockedBody))
        stub.enqueue(Self.decode(RippleAccountResponse.self, Self.accountInfoBody))
        let sleeper = RecordingSleeper()
        let service = RippleService(resolver: NoOverrideResolver(), httpClient: stub, sleep: sleeper.sleep)

        let info = try await service.fetchAccountsInfo(for: "rTestAccount")

        XCTAssertEqual(info?.result?.accountData?.balance, "5000000")
        XCTAssertEqual(stub.callCount, 2)
    }

    func testFetchAccountsInfoExhaustedThrowsRatherThanReturningEmptyBody() async {
        // Pins the Step 1 fix: a persistent amendmentBlocked must NOT resolve to
        // an empty account body (which would make getBalance report "0").
        let stub = SequencedHTTPClient()
        for _ in 0..<10 { stub.enqueue(Self.decode(RippleAccountResponse.self, Self.amendmentBlockedBody)) }
        let sleeper = RecordingSleeper()
        let service = RippleService(resolver: NoOverrideResolver(), httpClient: stub, sleep: sleeper.sleep)

        do {
            _ = try await service.fetchAccountsInfo(for: "rTestAccount")
            XCTFail("Expected exhaustion to throw rather than return an empty account body")
        } catch let error as RippleRetryError {
            guard case .exhausted(let rpcError) = error else {
                return XCTFail("Unexpected RippleRetryError: \(error)")
            }
            XCTAssertEqual(rpcError, "amendmentBlocked")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(stub.callCount, RippleRetryPolicy.maxAttempts)
    }

    // MARK: - Status lookup (the reported failure path)

    func testStatusLookupRetriesAmendmentBlockedThenConfirms() async throws {
        // Reproduces the reported bug: the tx already succeeded on-chain, but the
        // status check hit a stale backend and surfaced amendmentBlocked.
        let stub = SequencedHTTPClient()
        stub.enqueue(Self.decode(RippleTransactionStatusResponse.self, Self.statusAmendmentBlockedBody))
        stub.enqueue(Self.decode(RippleTransactionStatusResponse.self, Self.statusConfirmedBody))
        let sleeper = RecordingSleeper()
        let provider = RippleTransactionStatusProvider(httpClient: stub, sleep: sleeper.sleep)

        let result = try await provider.checkStatus(
            query: TransactionStatusQuery(txHash: "ABC123", chain: .ripple)
        )

        XCTAssertEqual(result.status, .confirmed)
        XCTAssertEqual(stub.callCount, 2)
        XCTAssertEqual(sleeper.count, 1)
        assertSameHost(stub, expected: RippleAPI.defaultHost)
    }

    // MARK: - Helpers

    /// Every request (initial + retries) must go to the same host — the fix is a
    /// same-host retry with no fallback list.
    private func assertSameHost(
        _ stub: SequencedHTTPClient,
        expected: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(stub.requestedHosts.isEmpty, "no request was made", file: file, line: line)
        XCTAssertEqual(Set(stub.requestedHosts).count, 1, "a retry switched hosts", file: file, line: line)
        for host in stub.requestedHosts {
            XCTAssertEqual(host, expected, file: file, line: line)
        }
    }

    // MARK: - Fixtures

    private static let amendmentBlockedBody = #"{"result":{"error":"amendmentBlocked","status":"error"}}"#
    private static let submitSuccessBody = #"""
    {"result":{"engine_result":"tesSUCCESS","engine_result_message":"ok","tx_json":{"hash":"ABC123"}}}
    """#
    private static let serverStateBody = #"""
    {"result":{"state":{"load_base":256,"load_factor":256,"validated_ledger":{"base_fee":10,"reserve_base":1000000,"reserve_inc":200000}}}}
    """#
    private static let accountInfoBody = #"""
    {"result":{"account_data":{"Account":"rTestAccount","Balance":"5000000","OwnerCount":0}}}
    """#
    private static let statusAmendmentBlockedBody = #"{"result":{"error":"amendmentBlocked","status":"error"}}"#
    private static let statusConfirmedBody = #"""
    {"result":{"validated":true,"ledger_index":123,"meta":{"TransactionResult":"tesSUCCESS"}}}
    """#

    private static func decode<T: Decodable>(_: T.Type, _ json: String) -> T {
        // swiftlint:disable:next force_try
        try! JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}

// MARK: - Test doubles

/// A minimal `RippleRPCResponse` for exercising the retry loop independently of
/// the concrete Ripple response types.
private struct FakeRippleResponse: Decodable, RippleRPCResponse {
    let rpcError: String?
    let tag: String
}

/// Records backoff calls without sleeping, so retry tests run instantly.
private final class RecordingSleeper: @unchecked Sendable {
    private(set) var count = 0
    private(set) var durations: [Duration] = []

    var sleep: RippleRequestRetrier.Sleeper {
        { [self] duration in
            count += 1
            durations.append(duration)
        }
    }
}

/// Resolver that never overrides — the service falls back to the default host.
private struct NoOverrideResolver: RPCEndpointResolving {
    func url(for _: Chain) -> String? { nil }
}

/// A trivial `TargetType` for driving the retrier in isolation.
private struct AnyTarget: TargetType {
    var baseURL: URL { RippleAPI.defaultHost }
    var path: String { "/" }
    var method: HTTPMethod { .post }
    var task: HTTPTask { .requestPlain }
}

/// Returns queued decoded values / errors in FIFO order and counts calls.
private final class SequencedHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    private enum Item {
        case value(Any)
        case error(Error)
    }

    private var items: [Item] = []
    private(set) var callCount = 0
    /// The base URL of every request the retrier issued, in order. Used to pin
    /// the SAME-HOST guarantee: a retry must reuse the same host (no fallback).
    private(set) var requestedHosts: [URL] = []

    func enqueue<T>(_ value: T) {
        items.append(.value(value))
    }

    func enqueueError(_ error: Error) {
        items.append(.error(error))
    }

    // SwiftLint can't see across the protocol conformance; the bodies are sync.
    // swiftlint:disable async_without_await
    func request(_: TargetType) async throws -> HTTPResponse<Data> {
        throw HTTPError.invalidResponse
    }

    func request<T: Decodable>(
        _ target: TargetType,
        responseType _: T.Type
    ) async throws -> HTTPResponse<T> {
        callCount += 1
        requestedHosts.append(target.baseURL)
        guard !items.isEmpty else {
            XCTFail("SequencedHTTPClient exhausted after \(callCount) calls")
            throw HTTPError.invalidResponse
        }
        let item = items.removeFirst()
        switch item {
        case .error(let error):
            throw error
        case .value(let raw):
            guard let typed = raw as? T else {
                XCTFail("Queued value type \(Swift.type(of: raw)) does not match \(T.self)")
                throw HTTPError.invalidResponse
            }
            let stub = HTTPURLResponse(
                url: RippleAPI.defaultHost,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return HTTPResponse(data: typed, response: stub)
        }
    }

    func requestEmpty(_: TargetType) async throws -> HTTPResponse<EmptyResponse> {
        throw HTTPError.invalidResponse
    }
    // swiftlint:enable async_without_await
}
