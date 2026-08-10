//
//  SuiEndpointFailoverTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

/// Sui shipped with one hardcoded host and no fallback, so a single unreachable
/// node took balances, fee estimates and broadcast down with it. These pin the
/// failover walk and — just as important — the cases where it must NOT fire.
final class SuiEndpointFailoverTests: XCTestCase {

    private static let primary = URL(staticString: "https://sui-primary.local")
    private static let secondary = URL(staticString: "https://sui-secondary.local")
    private static let tertiary = URL(staticString: "https://sui-tertiary.local")

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
        http.queueDecoded(SuiReferenceGasPriceResponse(result: "750", error: nil))

        let response = try await makeClient(hosts: [Self.primary, Self.secondary])
            .request(.referenceGasPrice, responseType: SuiReferenceGasPriceResponse.self)

        XCTAssertEqual(response.result, "750")
        XCTAssertEqual(http.requestedHosts, [Self.primary, Self.secondary])
    }

    func testFailoverWalksEveryHostInOrder() async throws {
        http.queueError(HTTPError.networkError(URLError(.cannotConnectToHost)))
        http.queueError(HTTPError.statusCode(503, nil))
        http.queueDecoded(SuiReferenceGasPriceResponse(result: "100", error: nil))

        let response = try await makeClient(hosts: [Self.primary, Self.secondary, Self.tertiary])
            .request(.referenceGasPrice, responseType: SuiReferenceGasPriceResponse.self)

        XCTAssertEqual(response.result, "100")
        XCTAssertEqual(http.requestedHosts, [Self.primary, Self.secondary, Self.tertiary])
    }

    func testAllHostsFailingThrowsTheLastTransportError() async {
        http.queueError(HTTPError.timeout)
        http.queueError(HTTPError.statusCode(502, nil))

        do {
            _ = try await makeClient(hosts: [Self.primary, Self.secondary])
                .request(.referenceGasPrice, responseType: SuiReferenceGasPriceResponse.self)
            XCTFail("Expected the last transport failure to be rethrown")
        } catch HTTPError.statusCode(let code, _) {
            XCTAssertEqual(code, 502)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(http.requestedHosts, [Self.primary, Self.secondary])
    }

    // MARK: - Cases where failover must NOT fire

    func testNodeRefusalIsSurfacedWithoutTryingOtherHosts() async throws {
        // A JSON-RPC `error` member arrives inside a well-formed HTTP 200 body.
        // The node understood the request and declined it, so replaying it
        // against every remaining host only delays the same answer.
        http.queueDecoded(SuiReferenceGasPriceResponse(
            result: nil,
            error: SuiRPCError(code: -32602, message: "invalid params")
        ))

        let response = try await makeClient(hosts: [Self.primary, Self.secondary])
            .request(.referenceGasPrice, responseType: SuiReferenceGasPriceResponse.self)

        XCTAssertEqual(response.error?.message, "invalid params")
        XCTAssertEqual(http.requestedHosts, [Self.primary])
    }

    func testARequestLevelRejectionIsNotReplayedAgainstOtherHosts() async {
        // A 400 is about the request, so the next host rejects it identically.
        // Replaying it wastes a round trip, sends signed material to another
        // operator for nothing, and buries this error under the last host's.
        http.queueError(HTTPError.statusCode(400, nil))
        http.queueDecoded(SuiReferenceGasPriceResponse(result: "100", error: nil))

        do {
            _ = try await makeClient(hosts: [Self.primary, Self.secondary])
                .request(.referenceGasPrice, responseType: SuiReferenceGasPriceResponse.self)
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

        for terminal: HTTPError in [
            .statusCode(400, nil),
            .statusCode(401, nil),
            .statusCode(403, nil),
            .statusCode(404, nil),
            .invalidURL,
            .encodingFailed
        ] {
            XCTAssertFalse(
                SuiFailoverPolicy.shouldTryNextHost(after: terminal),
                "expected no failover after \(terminal)"
            )
        }
    }

    func testAHostLocalMissKeepsWalkingAndReturnsTheLastMissWhenAllHostsMiss() async throws {
        // The generalized form of the status poller's problem: a response that
        // decoded fine but says "not here".
        http.queueDecoded(SuiReferenceGasPriceResponse(result: nil, error: nil))
        http.queueDecoded(SuiReferenceGasPriceResponse(result: nil, error: nil))

        let response = try await makeClient(hosts: [Self.primary, Self.secondary]).request(
            responseType: SuiReferenceGasPriceResponse.self,
            shouldTryNextHost: { $0.result == nil },
            makeTarget: { SuiAPI(baseURL: $0, endpoint: .referenceGasPrice) }
        )

        XCTAssertNil(response.result)
        XCTAssertEqual(http.requestedHosts, [Self.primary, Self.secondary])
    }

    func testCancellationPropagatesWithoutTryingOtherHosts() async {
        http.queueError(CancellationError())

        do {
            _ = try await makeClient(hosts: [Self.primary, Self.secondary])
                .request(.referenceGasPrice, responseType: SuiReferenceGasPriceResponse.self)
            XCTFail("Expected the cancellation to propagate")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(http.requestedHosts, [Self.primary])
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
        // A stored override that will not parse must not strand Sui on an empty
        // host list — it falls back rather than failing every request.
        for malformed in ["", "http://[not-a-host"] {
            let resolver = SuiEndpointResolver(
                resolver: FixedResolver(url: malformed),
                defaultHosts: [Self.primary, Self.secondary]
            )

            XCTAssertEqual(resolver.hosts(), [Self.primary, Self.secondary], "override: \(malformed)")
        }
    }

    func testAnEmptyDefaultListStillYieldsAHost() {
        // A zero-host transport would fail every request with
        // `noEndpointsConfigured` instead of talking to Sui at all.
        let resolver = SuiEndpointResolver(resolver: FixedResolver(url: nil), defaultHosts: [])

        XCTAssertEqual(resolver.hosts(), [SuiAPI.defaultHost])
    }

    func testShippedDefaultsLeadWithTheHistoricalHost() {
        XCTAssertEqual(SuiAPI.defaultHosts.first, SuiAPI.defaultHost)
        XCTAssertEqual(SuiAPI.defaultHost.absoluteString, "https://sui-rpc.publicnode.com")
        XCTAssertGreaterThan(SuiAPI.defaultHosts.count, 1, "Sui must ship with a fallback host")
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

/// Returns the stored override verbatim, so the resolver's own parse guard is
/// what the tests exercise.
private struct FixedResolver: RPCEndpointResolving {
    let overrideURL: String?

    init(url: String?) {
        self.overrideURL = url
    }

    func url(for _: Chain) -> String? { overrideURL }
}

/// Replays a FIFO queue of outcomes and records the host of every attempt, so a
/// test can assert the exact failover sequence.
private final class SequencedHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    private enum Outcome {
        case value(Any)
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

    func queueDecoded<T>(_ value: T) {
        lock.lock()
        defer { lock.unlock() }
        queue.append(.value(value))
    }

    func queueError(_ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        queue.append(.error(error))
    }

    // Protocol requires `async`; the body is sync. SwiftLint can't see across
    // protocol conformance, so silence the false-positive lint here.
    // swiftlint:disable async_without_await
    func request(_: TargetType) async throws -> HTTPResponse<Data> {
        // Only the typed overload is exercised; this path should not run.
        throw HTTPError.invalidResponse
    }

    func request<T: Decodable>(_ target: TargetType, responseType _: T.Type) async throws -> HTTPResponse<T> {
        lock.lock()
        recorded.append(target.baseURL)
        let next = queue.isEmpty ? nil : queue.removeFirst()
        lock.unlock()

        switch next {
        case .value(let value):
            guard let typed = value as? T else { throw HTTPError.invalidResponse }
            return HTTPResponse(data: typed, response: Self.okResponse(url: target.baseURL))
        case .error(let error):
            throw error
        case nil:
            throw HTTPError.noData
        }
    }
    // swiftlint:enable async_without_await

    private static func okResponse(url: URL) -> HTTPURLResponse {
        // Force-unwrap is safe: a 200 response for a valid URL always initializes.
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }
}
