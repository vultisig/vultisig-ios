//
//  SuiTransactionStatusProviderTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

/// The status poller decides whether a transaction the user has already signed
/// and broadcast is confirmed, still pending, or failed — and the poller records
/// `failed` as terminal, so a misread is not recoverable from the UI.
///
/// Two classes of bug are pinned here. One predates GraphQL: the poller built its
/// URL from the hardcoded default while `SuiService` honoured the user's custom
/// RPC, so anyone on a custom node polled a host that had never seen the digest.
/// The other arrives with it: GraphQL spells the execution status `SUCCESS` where
/// JSON-RPC spelled it `success`, and a comparison left on the old spelling reads
/// every confirmed transaction as failed.
final class SuiTransactionStatusProviderTests: XCTestCase {

    private static let query = TransactionStatusQuery(txHash: "0xdigest", chain: .sui)

    private var http: RecordingHTTPClient!

    override func setUp() {
        super.setUp()
        http = RecordingHTTPClient()
    }

    override func tearDown() {
        http = nil
        super.tearDown()
    }

    // MARK: - Host resolution

    func testCheckStatusUsesCustomRPCOverrideHost() async throws {
        let override = "https://sui-status-override.local/rpc"
        let provider = SuiTransactionStatusProvider(
            httpClient: http,
            resolver: FixedSuiResolver(url: override)
        )
        http.queue(Self.confirmed())

        _ = try await provider.checkStatus(query: Self.query)

        XCTAssertEqual(http.requestedURLs.map(\.absoluteString), [override])
    }

    func testCheckStatusFallsBackToDefaultHostWithoutOverride() async throws {
        let provider = makeProvider()
        http.queue(Self.confirmed())

        _ = try await provider.checkStatus(query: Self.query)

        XCTAssertEqual(http.requestedURLs, [SuiService.defaultRPCURL])
    }

    func testCheckStatusSendsTheDigestAsAGraphQLVariable() async throws {
        let provider = makeProvider()
        http.queue(Self.confirmed())

        _ = try await provider.checkStatus(query: Self.query)

        let body = try XCTUnwrap(http.recordedBodies.first)
        XCTAssertEqual((body["variables"] as? [String: Any])?["digest"] as? String, "0xdigest")
        XCTAssertTrue((body["query"] as? String)?.contains("transaction(digest:") == true)
    }

    // MARK: - Status mapping

    func testUppercaseSuccessMapsToConfirmed() async throws {
        // The spelling change that would otherwise report every confirmed
        // transaction as pending until the poll timed out.
        let provider = makeProvider()
        http.queue(Self.confirmed(checkpoint: 42))

        let result = try await provider.checkStatus(query: Self.query)

        XCTAssertEqual(result.status, .confirmed)
        XCTAssertEqual(result.blockNumber, 42)
    }

    func testFailureMapsToFailedWithTheExecutionError() async throws {
        let provider = makeProvider()
        http.queue(Data("""
        {"data":{"transaction":{"digest":"0xdigest","effects":{"status":"FAILURE",\
        "executionError":{"message":"MoveAbort(...) in command 0","abortCode":null,"identifier":null},\
        "checkpoint":{"sequenceNumber":7}}}}}
        """.utf8))

        let result = try await provider.checkStatus(query: Self.query)

        XCTAssertEqual(result.status, .failed(reason: "MoveAbort(...) in command 0"))
        XCTAssertEqual(result.blockNumber, 7)
    }

    func testAnUnknownStatusStaysPendingRatherThanFailingTerminally() async throws {
        // The poller records `.failed` as terminal and the user cannot undo it,
        // so a status Sui adds later — or omits — must not condemn the
        // transaction. Only an explicit FAILURE is a failure.
        let provider = makeProvider()
        http.queue(Data("""
        {"data":{"transaction":{"digest":"0xdigest","effects":{"status":"SOMETHING_NEW",\
        "executionError":null,"checkpoint":null}}}}
        """.utf8))

        let result = try await provider.checkStatus(query: Self.query)

        XCTAssertEqual(result.status, .pending)
    }

    func testAnAbsentStatusStaysPending() async throws {
        let provider = makeProvider()
        http.queue(Data("""
        {"data":{"transaction":{"digest":"0xdigest","effects":{"status":null,\
        "executionError":null,"checkpoint":null}}}}
        """.utf8))

        let result = try await provider.checkStatus(query: Self.query)

        XCTAssertEqual(result.status, .pending)
    }

    func testARecordWithoutEffectsIsPendingNotAbsent() async throws {
        // The node returned a transaction record, which proves it knows the
        // digest — it just has not finished populating it. Reporting `notFound`
        // would misstate what the node said.
        let provider = makeProvider()
        http.queue(Data(#"{"data":{"transaction":{"digest":"0xdigest","effects":null}}}"#.utf8))

        let result = try await provider.checkStatus(query: Self.query)

        XCTAssertEqual(result.status, .pending)
    }

    func testANullTransactionMapsToNotFound() async throws {
        // A digest that hasn't landed resolves to null with no errors — safe to
        // keep polling, and distinct from a refusal.
        //
        // Pinned to one host on purpose: a null transaction is a host-local
        // miss, so with a longer list the provider would walk it and this test
        // would be asserting failover instead of mapping. The shipped default
        // list gains a second entry as soon as a second Sui GraphQL endpoint
        // exists, and that must not silently change what this test measures.
        let provider = makeProvider(hosts: [Self.singleHost])
        http.queue(Data(#"{"data":{"transaction":null}}"#.utf8))

        let result = try await provider.checkStatus(query: Self.query)

        XCTAssertEqual(result.status, .notFound)
    }

    func testANodeRefusalIsRaisedRatherThanReportedAsNotFound() async {
        // A populated `errors` array is the node saying it cannot answer. Masking
        // it as not-found would poll a persistent failure until timeout.
        let provider = makeProvider()
        http.queue(Data(
            #"{"data":null,"errors":[{"message":"indexer unavailable","extensions":{"code":"INTERNAL_SERVER_ERROR"}}]}"#.utf8
        ))

        do {
            _ = try await provider.checkStatus(query: Self.query)
            XCTFail("Expected the node refusal to be raised")
        } catch let error as SuiRPCError {
            XCTAssertEqual(error, .node(message: "indexer unavailable", code: "INTERNAL_SERVER_ERROR"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAResponseAboutADifferentTransactionIsRejected() async {
        // A custom or buggy endpoint answering with someone else's digest would
        // otherwise have THAT transaction's outcome recorded against this send —
        // and the poller writes failure permanently.
        let provider = makeProvider()
        http.queue(Data("""
        {"data":{"transaction":{"digest":"0xsomeoneelse","effects":{"status":"FAILURE",\
        "executionError":{"message":"not ours","abortCode":null,"identifier":null},"checkpoint":null}}}}
        """.utf8))

        do {
            _ = try await provider.checkStatus(query: Self.query)
            XCTFail("Expected the digest mismatch to be rejected")
        } catch let error as SuiRPCError {
            XCTAssertEqual(error, .digestMismatch(requested: "0xdigest", returned: "0xsomeoneelse"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testA404IsNotReportedAsNotFound() async {
        // Absence is `transaction: null`. A 404 means the endpoint did not serve
        // the request — a wrong custom-RPC path, or the last host in a partial
        // outage — and calling that "not found" would hide a broken endpoint
        // behind "still pending" until the poll timed out.
        // One host: a 404 is retryable, so a longer list would walk past it and
        // surface whatever the next host said instead.
        let provider = makeProvider(hosts: [Self.singleHost])
        http.queueError(HTTPError.statusCode(404, nil))

        do {
            _ = try await provider.checkStatus(query: Self.query)
            XCTFail("Expected the 404 to propagate")
        } catch HTTPError.statusCode(let code, _) {
            XCTAssertEqual(code, 404)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Cross-host lookup

    func testADigestMissingFromTheFirstHostIsLookedUpOnTheNext() async throws {
        // A transaction broadcast through the fallback host is legitimately
        // unknown to the primary, and a pruned node can miss a digest its peer
        // already has. Stopping at the first miss would poll a landed
        // transaction until the poller gave up.
        let hosts = [
            URL(staticString: "https://sui-a.local"),
            URL(staticString: "https://sui-b.local")
        ]
        let provider = SuiTransactionStatusProvider(
            httpClient: http,
            resolver: FixedSuiResolver(url: nil),
            hosts: hosts
        )
        http.queue(Data(#"{"data":{"transaction":null}}"#.utf8))
        http.queue(Self.confirmed(checkpoint: 88))

        let result = try await provider.checkStatus(query: Self.query)

        XCTAssertEqual(result.status, .confirmed)
        XCTAssertEqual(result.blockNumber, 88)
        XCTAssertEqual(http.requestedURLs, hosts)
    }

    // MARK: - Helpers

    /// A single explicit host, for tests whose subject is response mapping
    /// rather than failover.
    private static let singleHost = URL(staticString: "https://sui-only.local")

    private func makeProvider(
        hosts: [URL] = SuiGraphQLAPI.defaultHosts
    ) -> SuiTransactionStatusProvider {
        SuiTransactionStatusProvider(httpClient: http, resolver: FixedSuiResolver(url: nil), hosts: hosts)
    }

    private static func confirmed(checkpoint: Int? = nil) -> Data {
        let checkpointJSON = checkpoint.map { "{\"sequenceNumber\":\($0)}" } ?? "null"
        return Data("""
        {"data":{"transaction":{"digest":"0xdigest","effects":{"status":"SUCCESS",\
        "executionError":null,"checkpoint":\(checkpointJSON)}}}}
        """.utf8)
    }
}

/// Returns a fixed override for every chain, or none when `overrideURL` is `nil`.
private struct FixedSuiResolver: RPCEndpointResolving {
    let overrideURL: String?

    init(url: String?) {
        self.overrideURL = url
    }

    func url(for _: Chain) -> String? { overrideURL }
}

/// Records the URL and body of every request and replays queued raw payloads
/// through the real `JSONDecoder`, so the GraphQL envelope and the selection-set
/// types are exercised rather than assumed.
private final class RecordingHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    private enum Outcome {
        case payload(Data)
        case error(Error)
    }

    private let lock = NSLock()
    private var outcomes: [Outcome] = []
    private var recorded: [URL] = []
    private var bodies: [[String: Any]] = []

    var requestedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var recordedBodies: [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return bodies
    }

    func queue(_ payload: Data) {
        lock.lock()
        defer { lock.unlock() }
        outcomes.append(.payload(payload))
    }

    func queueError(_ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        outcomes.append(.error(error))
    }

    // Protocol requires `async`; the body is sync. SwiftLint can't see across
    // protocol conformance, so silence the false-positive lint here.
    // swiftlint:disable async_without_await
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        lock.lock()
        recorded.append(target.baseURL)
        if case .requestParameters(let body, _) = target.task {
            bodies.append(body)
        }
        let next = outcomes.isEmpty ? nil : outcomes.removeFirst()
        lock.unlock()

        switch next {
        case .payload(let data):
            // Force-unwrap is safe: a 200 response for a valid URL always initializes.
            let response = HTTPURLResponse(url: target.baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return HTTPResponse(data: data, response: response)
        case .error(let error):
            throw error
        case nil:
            throw HTTPError.noData
        }
    }
    // swiftlint:enable async_without_await
}
