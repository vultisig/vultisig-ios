//
//  SuiEndpointFailoverTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

/// Sui shipped with one hardcoded host and no fallback, so a single unreachable
/// node took balances, fee estimates and broadcast down with it. The GraphQL
/// endpoint list has one entry today — `graphql.mainnet.sui.io` is the only
/// public Sui GraphQL host that answers — so these pin the seam that makes a
/// second host a configuration change, and, just as importantly, the cases where
/// failover must NOT fire.
final class SuiEndpointFailoverTests: XCTestCase {

    private static let primary = URL(staticString: "https://sui-primary.local")
    private static let secondary = URL(staticString: "https://sui-secondary.local")
    private static let tertiary = URL(staticString: "https://sui-tertiary.local")

    private static let gasPrice = #"{"data":{"epoch":{"referenceGasPrice":"750"}}}"#

    private var http: SequencedHTTPClient!

    override func setUp() {
        super.setUp()
        http = SequencedHTTPClient()
    }

    override func tearDown() {
        http = nil
        super.tearDown()
    }

    // MARK: - Failover on transport faults

    func testFirstHostTransportFailureFallsBackToSecond() async throws {
        http.queueError(HTTPError.timeout)
        http.queue(Data(Self.gasPrice.utf8))

        let data = try await makeClient(hosts: [Self.primary, Self.secondary])
            .query(SuiGraphQLDocument.referenceGasPrice, responseType: SuiEpochData.self)

        XCTAssertEqual(data.epoch?.referenceGasPrice, "750")
        XCTAssertEqual(http.requestedHosts, [Self.primary, Self.secondary])
    }

    func testFailoverWalksEveryHostInOrder() async throws {
        http.queueError(HTTPError.networkError(URLError(.cannotConnectToHost)))
        http.queueError(HTTPError.statusCode(503, nil))
        http.queue(Data(Self.gasPrice.utf8))

        let data = try await makeClient(hosts: [Self.primary, Self.secondary, Self.tertiary])
            .query(SuiGraphQLDocument.referenceGasPrice, responseType: SuiEpochData.self)

        XCTAssertEqual(data.epoch?.referenceGasPrice, "750")
        XCTAssertEqual(http.requestedHosts, [Self.primary, Self.secondary, Self.tertiary])
    }

    func testAllHostsFailingThrowsTheLastTransportError() async {
        http.queueError(HTTPError.timeout)
        http.queueError(HTTPError.statusCode(502, nil))

        do {
            _ = try await makeClient(hosts: [Self.primary, Self.secondary])
                .query(SuiGraphQLDocument.referenceGasPrice, responseType: SuiEpochData.self)
            XCTFail("Expected the last transport failure to be rethrown")
        } catch HTTPError.statusCode(let code, _) {
            XCTAssertEqual(code, 502)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(http.requestedHosts, [Self.primary, Self.secondary])
    }

    // MARK: - GraphQL node errors

    func testARetryableNodeErrorFailsOverToTheNextHost() async throws {
        // The node was reached but could not answer this time. A broadcast is
        // safe to replay because Sui keys a transaction by the digest of its
        // signed bytes, so re-submitting identical bytes is idempotent.
        http.queue(Data(
            #"{"data":null,"errors":[{"message":"overloaded","extensions":{"code":"INTERNAL_SERVER_ERROR"}}]}"#.utf8
        ))
        http.queue(Data(Self.gasPrice.utf8))

        let data = try await makeClient(hosts: [Self.primary, Self.secondary])
            .query(SuiGraphQLDocument.referenceGasPrice, responseType: SuiEpochData.self)

        XCTAssertEqual(data.epoch?.referenceGasPrice, "750")
        XCTAssertEqual(http.requestedHosts, [Self.primary, Self.secondary])
    }

    func testANodeVerdictIsRaisedWithoutTryingOtherHosts() async {
        // A refusal the node has already judged reads the same everywhere, so
        // replaying it only delays the identical answer — and on the fund path
        // it means sending signed material to another operator for nothing.
        http.queue(Data(
            #"{"data":null,"errors":[{"message":"invalid signature","extensions":{"code":"BAD_USER_INPUT"}}]}"#.utf8
        ))

        do {
            _ = try await makeClient(hosts: [Self.primary, Self.secondary])
                .query(SuiGraphQLDocument.referenceGasPrice, responseType: SuiEpochData.self)
            XCTFail("Expected the node verdict to be raised")
        } catch let error as SuiRPCError {
            XCTAssertEqual(error, .node(message: "invalid signature", code: "BAD_USER_INPUT"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(http.requestedHosts, [Self.primary])
    }

    func testAnEnvelopeWithNeitherDataNorErrorsIsMalformed() async {
        // GraphQL answers HTTP 200 even when it refuses, so this is never an
        // empty result.
        http.queue(Data("{}".utf8))
        http.queue(Data("{}".utf8))

        do {
            _ = try await makeClient(hosts: [Self.primary]).query(
                SuiGraphQLDocument.referenceGasPrice,
                responseType: SuiEpochData.self
            )
            XCTFail("Expected a malformed-response error")
        } catch let error as SuiRPCError {
            XCTAssertEqual(error, .malformedResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAJSONRPCEnvelopeIsReportedAsALegacyEndpoint() async {
        // Only a custom RPC saved before the migration can produce this, and the
        // fix is the user's to make — so it must not read as "the node is broken".
        http.queue(Data(
            #"{"jsonrpc":"2.0","error":{"code":-32600,"message":"Invalid Request"},"id":null}"#.utf8
        ))

        do {
            _ = try await makeClient(hosts: [Self.primary]).query(
                SuiGraphQLDocument.referenceGasPrice,
                responseType: SuiEpochData.self
            )
            XCTFail("Expected the legacy-endpoint error")
        } catch let error as SuiRPCError {
            XCTAssertEqual(error, .legacyJSONRPCEndpoint(host: Self.primary.absoluteString))
            XCTAssertTrue(error.localizedDescription.contains("JSON-RPC"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Cases where failover must NOT fire

    func testARequestLevelRejectionIsNotReplayedAgainstOtherHosts() async {
        http.queueError(HTTPError.statusCode(400, nil))
        http.queue(Data(Self.gasPrice.utf8))

        do {
            _ = try await makeClient(hosts: [Self.primary, Self.secondary])
                .query(SuiGraphQLDocument.referenceGasPrice, responseType: SuiEpochData.self)
            XCTFail("Expected the rejection to be rethrown immediately")
        } catch HTTPError.statusCode(let code, _) {
            XCTAssertEqual(code, 400)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(http.requestedHosts, [Self.primary])
    }

    func testFailoverClassifierSplitsHostFaultsFromRequestFaults() {
        for retryable: HTTPError in [
            .timeout,
            .networkError(URLError(.notConnectedToInternet)),
            .invalidSSLCertificate,
            .invalidResponse,
            .noData,
            .decodingFailed(URLError(.badServerResponse)),
            .statusCode(500, nil),
            .statusCode(503, nil),
            .statusCode(408, nil),
            .statusCode(429, nil)
        ] {
            XCTAssertTrue(
                SuiFailoverPolicy.shouldTryNextHost(after: retryable),
                "expected failover after \(retryable)"
            )
        }

        // Host policy and capability, not request defects.
        for hostFault: HTTPError in [.statusCode(401, nil), .statusCode(403, nil), .statusCode(404, nil)] {
            XCTAssertTrue(
                SuiFailoverPolicy.shouldTryNextHost(after: hostFault),
                "expected failover after \(hostFault)"
            )
        }

        for terminal: HTTPError in [
            .statusCode(400, nil),
            .statusCode(413, nil),
            .statusCode(422, nil),
            .invalidURL,
            .encodingFailed
        ] {
            XCTAssertFalse(
                SuiFailoverPolicy.shouldTryNextHost(after: terminal),
                "expected no failover after \(terminal)"
            )
        }
    }

    func testCancellationPropagatesWithoutTryingOtherHosts() async {
        http.queueError(CancellationError())

        do {
            _ = try await makeClient(hosts: [Self.primary, Self.secondary])
                .query(SuiGraphQLDocument.referenceGasPrice, responseType: SuiEpochData.self)
            XCTFail("Expected the cancellation to propagate")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(http.requestedHosts, [Self.primary])
    }

    func testAMissPlusAnUnansweredHostThrowsRatherThanReportingTheMiss() async {
        // "Not here" from one host and silence from another is not the same
        // evidence as "not here" from all of them.
        http.queue(Data(#"{"data":{"transaction":null}}"#.utf8))
        http.queueError(HTTPError.statusCode(503, nil))

        do {
            _ = try await makeClient(hosts: [Self.primary, Self.secondary]).query(
                SuiGraphQLDocument.transaction,
                variables: ["digest": "0xabc"],
                responseType: SuiTransactionData.self,
                shouldTryNextHost: { $0.transaction == nil }
            )
            XCTFail("Expected the unanswered host's failure to be thrown")
        } catch HTTPError.statusCode(let code, _) {
            XCTAssertEqual(code, 503)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(http.requestedHosts, [Self.primary, Self.secondary])
    }

    func testAHostLocalMissReturnsTheLastMissWhenEveryHostMisses() async throws {
        http.queue(Data(#"{"data":{"transaction":null}}"#.utf8))
        http.queue(Data(#"{"data":{"transaction":null}}"#.utf8))

        let data = try await makeClient(hosts: [Self.primary, Self.secondary]).query(
            SuiGraphQLDocument.transaction,
            variables: ["digest": "0xabc"],
            responseType: SuiTransactionData.self,
            shouldTryNextHost: { $0.transaction == nil }
        )

        XCTAssertNil(data.transaction)
        XCTAssertEqual(http.requestedHosts, [Self.primary, Self.secondary])
    }

    // MARK: - Host resolution

    func testCustomOverrideCollapsesTheListToTheUsersHost() {
        // The user picked a node. Falling back to a public host would both
        // defeat that choice and leak their addresses to an operator they did
        // not select.
        let resolver = SuiEndpointResolver(
            resolver: FixedResolver(url: "https://my-sui-node.example"),
            defaultHosts: [Self.primary, Self.secondary]
        )

        XCTAssertEqual(resolver.hosts().map(\.absoluteString), ["https://my-sui-node.example"])
    }

    func testWithoutAnOverrideTheDefaultListIsUsedInOrder() {
        let resolver = SuiEndpointResolver(
            resolver: FixedResolver(url: nil),
            defaultHosts: [Self.primary, Self.secondary]
        )

        XCTAssertEqual(resolver.hosts(), [Self.primary, Self.secondary])
    }

    func testUnparseableOverrideFallsBackToTheDefaultList() {
        for malformed in ["", "http://[not-a-host"] {
            let resolver = SuiEndpointResolver(
                resolver: FixedResolver(url: malformed),
                defaultHosts: [Self.primary, Self.secondary]
            )

            XCTAssertEqual(resolver.hosts(), [Self.primary, Self.secondary], "override: \(malformed)")
        }
    }

    func testAnEmptyDefaultListStillYieldsAHost() {
        let resolver = SuiEndpointResolver(resolver: FixedResolver(url: nil), defaultHosts: [])

        XCTAssertEqual(resolver.hosts(), [SuiGraphQLAPI.defaultHost])
    }

    func testShippedDefaultsPointAtSuiGraphQL() {
        // JSON-RPC is being decommissioned; nothing in the default list may
        // still point at a JSON-RPC-only host.
        XCTAssertEqual(SuiGraphQLAPI.defaultHosts, [SuiGraphQLAPI.defaultHost])
        XCTAssertEqual(
            SuiGraphQLAPI.defaultHost.absoluteString,
            "https://graphql.mainnet.sui.io/graphql"
        )
        XCTAssertEqual(SuiService.defaultRPCURL, SuiGraphQLAPI.defaultHost)
    }

    // MARK: - Helpers

    private func makeClient(hosts: [URL]) -> SuiFailoverClient {
        SuiFailoverClient(httpClient: http, endpoints: StaticEndpoints(urls: hosts))
    }
}

private struct StaticEndpoints: SuiEndpointProviding {
    let urls: [URL]

    func hosts() -> [URL] { urls }
}

private struct FixedResolver: RPCEndpointResolving {
    let overrideURL: String?

    init(url: String?) {
        self.overrideURL = url
    }

    func url(for _: Chain) -> String? { overrideURL }
}

/// Replays a FIFO queue of raw payloads through the real `JSONDecoder` and
/// records the host of every attempt, so a test can assert the exact failover
/// sequence.
private final class SequencedHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    private enum Outcome {
        case payload(Data)
        case error(Error)
    }

    private let lock = NSLock()
    private var queue: [Outcome] = []
    private var recorded: [URL] = []

    var requestedHosts: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func queue(_ payload: Data) {
        lock.lock()
        defer { lock.unlock() }
        queue.append(.payload(payload))
    }

    func queueError(_ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        queue.append(.error(error))
    }

    // Protocol requires `async`; the body is sync. SwiftLint can't see across
    // protocol conformance, so silence the false-positive lint here.
    // swiftlint:disable async_without_await
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        lock.lock()
        recorded.append(target.baseURL)
        let next = queue.isEmpty ? nil : queue.removeFirst()
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
