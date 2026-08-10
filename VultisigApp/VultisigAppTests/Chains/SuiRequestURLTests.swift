//
//  SuiRequestURLTests.swift
//  VultisigAppTests
//
//  Pins the URL that actually goes on the wire.
//
//  This exists because the whole Sui GraphQL migration shipped broken and 5369
//  tests stayed green. Every Sui test stubbed `HTTPClientProtocol` and asserted
//  against `target.baseURL`, so none of them saw what `HTTPClient` composes from
//  it — and `URL.appendingPathComponent("")` appends a trailing slash, turning
//  `https://graphql.mainnet.sui.io/graphql` into `.../graphql/`, which that
//  endpoint answers with a 404. Live `curl` probes did not catch it either:
//  they proved the endpoint works, never that the URL the app builds works.
//
//  So these tests deliberately do NOT stub `HTTPClientProtocol`. They drive the
//  real `HTTPClient` through a real `URLSession` and capture the request at the
//  `URLProtocol` boundary — the last point before the socket. An assertion any
//  further up the stack cannot see this class of bug.
//

@testable import VultisigApp
import XCTest

final class SuiRequestURLTests: XCTestCase {

    override func setUp() {
        super.setUp()
        URLCapturingProtocol.reset()
    }

    override func tearDown() {
        URLCapturingProtocol.reset()
        super.tearDown()
    }

    // MARK: - The URL on the wire

    func testSuiGraphQLRequestsTheEndpointWithoutATrailingSlash() async throws {
        let target = SuiGraphQLAPI(
            baseURL: SuiGraphQLAPI.defaultHost,
            document: SuiGraphQLDocument.referenceGasPrice
        )

        let requested = try await capturedURL(for: target)

        XCTAssertEqual(requested, "https://graphql.mainnet.sui.io/graphql")
        XCTAssertFalse(requested.hasSuffix("/"), "Sui's GraphQL endpoint 404s on the trailing-slash form")
    }

    func testEveryShippedSuiHostComposesWithoutATrailingSlash() async throws {
        for host in SuiGraphQLAPI.defaultHosts {
            let target = SuiGraphQLAPI(baseURL: host, document: SuiGraphQLDocument.referenceGasPrice)

            let requested = try await capturedURL(for: target)

            XCTAssertEqual(requested, host.absoluteString, "host must be requested verbatim: \(host)")
        }
    }

    func testTheStatusPollerRequestsTheSameURLAsTheReads() async throws {
        // Drives the real provider, not a hand-built target: if the poller ever
        // constructs its request differently, a user could see reads work and
        // status polling 404, and asserting on a target we built here would not
        // notice.
        let reads = try await capturedURL(
            for: SuiGraphQLAPI(baseURL: SuiGraphQLAPI.defaultHost, document: SuiGraphQLDocument.referenceGasPrice)
        )

        URLCapturingProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLCapturingProtocol.self]
        let provider = SuiTransactionStatusProvider(
            httpClient: HTTPClient(session: URLSession(configuration: configuration)),
            resolver: OverrideResolver(url: nil)
        )

        _ = try? await provider.checkStatus(query: TransactionStatusQuery(txHash: "0xdigest", chain: .sui))

        let status = try XCTUnwrap(URLCapturingProtocol.lastURL?.absoluteString)
        XCTAssertEqual(status, "https://graphql.mainnet.sui.io/graphql")
        XCTAssertEqual(reads, status)
    }

    // MARK: - Composition rules

    func testAnEmptyPathAppendsNothing() async throws {
        // The rule that was wrong. A base URL carrying a path must be requested
        // exactly as configured.
        let requested = try await capturedURL(
            for: StubTarget(baseURL: URL(staticString: "https://example.com/api/graphql"), path: "")
        )

        XCTAssertEqual(requested, "https://example.com/api/graphql")
    }

    func testANonEmptyPathIsStillAppended() async throws {
        let requested = try await capturedURL(
            for: StubTarget(baseURL: URL(staticString: "https://example.com"), path: "/v1/status")
        )

        XCTAssertEqual(requested, "https://example.com/v1/status")
    }

    func testABaseURLThatAlreadyEndsInASlashIsUnchanged() async throws {
        // Several proxied chains are configured this way and must not move.
        let requested = try await capturedURL(
            for: StubTarget(baseURL: URL(staticString: "https://api.vultisig.com/dot/"), path: "")
        )

        XCTAssertEqual(requested, "https://api.vultisig.com/dot/")
    }

    // MARK: - Custom RPC

    func testAPastedCustomEndpointWithATrailingSlashStillResolves() {
        // Typing or pasting a trailing slash is ordinary; 404ing on it is not
        // something a user could diagnose.
        let resolver = SuiEndpointResolver(
            resolver: OverrideResolver(url: "https://my-sui.example/graphql/")
        )

        XCTAssertEqual(resolver.hosts().map(\.absoluteString), ["https://my-sui.example/graphql"])
    }

    func testACustomOriginWithoutAPathKeepsItsForm() {
        // Nothing to strip: `https://host/` and `https://host` are the same
        // request, so leave the user's input alone.
        let resolver = SuiEndpointResolver(resolver: OverrideResolver(url: "https://my-sui.example/"))

        XCTAssertEqual(resolver.hosts().map(\.absoluteString), ["https://my-sui.example/"])
    }

    func testNormalizationTouchesOnlyThePath() {
        // Hosted providers put API keys in the query string. Trimming the URL
        // string instead of the path component would corrupt a key that happens
        // to end in `/`, and would miss the unwanted path slash entirely
        // whenever a query follows it.
        let cases: [(input: String, expected: String)] = [
            ("https://h.example/graphql/?apiKey=x", "https://h.example/graphql?apiKey=x"),
            ("https://h.example/graphql?apiKey=abc/", "https://h.example/graphql?apiKey=abc/"),
            ("https://h.example/graphql/#frag/", "https://h.example/graphql#frag/"),
            ("https://h.example:8443/graphql/", "https://h.example:8443/graphql"),
            ("https://h.example/a%2Fb/", "https://h.example/a%2Fb"),
            ("https://h.example/", "https://h.example/")
        ]

        for testCase in cases {
            let resolver = SuiEndpointResolver(resolver: OverrideResolver(url: testCase.input))
            XCTAssertEqual(resolver.hosts().map(\.absoluteString), [testCase.expected], testCase.input)
        }
    }

    func testTheLegacyEndpointErrorNamesTheHostWithoutItsCredentials() {
        // This value is shown on screen AND logged by generic keysign sinks, so
        // it must identify the endpoint without carrying the API key a hosted
        // provider keeps in the path or query.
        let error = SuiRPCError.legacyEndpoint(
            URL(staticString: "https://node.example:8443/rpc/SECRETKEY?apiKey=alsosecret")
        )

        XCTAssertEqual(error, .legacyJSONRPCEndpoint(host: "https://node.example:8443"))
        let description = try? XCTUnwrap(error.errorDescription)
        XCTAssertFalse(description?.contains("SECRETKEY") ?? true)
        XCTAssertFalse(description?.contains("alsosecret") ?? true)
        XCTAssertTrue(description?.contains("node.example") ?? false)
    }

    // MARK: - Helpers

    /// Drives the real `HTTPClient` over a real `URLSession` and returns the URL
    /// the request carried when it reached the protocol layer.
    private func capturedURL(for target: TargetType) async throws -> String {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLCapturingProtocol.self]
        let client = HTTPClient(session: URLSession(configuration: configuration))

        _ = try? await client.request(target)

        return try XCTUnwrap(URLCapturingProtocol.lastURL?.absoluteString)
    }
}

private struct StubTarget: TargetType {
    let baseURL: URL
    let path: String
    var method: HTTPMethod { .post }
    var task: HTTPTask { .requestParameters(["query": "{ __typename }"], .jsonEncoding) }
}

private struct OverrideResolver: RPCEndpointResolving {
    let overrideURL: String?

    init(url: String?) {
        self.overrideURL = url
    }

    func url(for _: Chain) -> String? { overrideURL }
}

/// Records the request URL at the last point before the socket, then answers a
/// minimal success so the client returns normally.
private final class URLCapturingProtocol: URLProtocol {

    private static let lock = NSLock()
    private static var captured: URL?

    static var lastURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        captured = nil
    }

    // These are required `URLProtocol` class-method overrides; they cannot be `static`.
    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        lock.lock()
        captured = request.url
        lock.unlock()
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        // Force-unwraps are safe: the URL came from the intercepted request and
        // a 200 response always initializes.
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"data":{}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
