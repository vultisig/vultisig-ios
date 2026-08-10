//
//  SuiTransactionStatusProviderTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

/// The status poller must query the same node that broadcast the transaction.
/// It previously built its URL from the hardcoded default while `SuiService`
/// honoured the user's custom RPC override, so a user on a custom node polled a
/// host that had never seen the digest and saw a live transaction as `notFound`.
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
        http.queueDecoded(Self.response(status: "success"))

        _ = try await provider.checkStatus(query: Self.query)

        XCTAssertEqual(http.requestedURLs.map(\.absoluteString), [override])
    }

    func testCheckStatusFallsBackToDefaultHostWithoutOverride() async throws {
        let provider = SuiTransactionStatusProvider(
            httpClient: http,
            resolver: FixedSuiResolver(url: nil)
        )
        http.queueDecoded(Self.response(status: "success"))

        _ = try await provider.checkStatus(query: Self.query)

        XCTAssertEqual(http.requestedURLs, [SuiService.defaultRPCURL])
    }

    func testStatusPollerAndServiceResolveTheSameHost() {
        // Both sides must read the same chain key and the same default, or the
        // poller drifts off the node that broadcast.
        let override = "https://sui-shared-host.local/rpc"
        let resolver = FixedSuiResolver(url: override)

        XCTAssertEqual(
            resolver.resolvedURL(for: .sui, default: SuiService.defaultRPCURL).absoluteString,
            override
        )
    }

    // MARK: - Mapping (unchanged by the host fix, pinned so it stays that way)

    func testSuccessfulEffectsMapToConfirmed() async throws {
        let provider = makeProvider()
        http.queueDecoded(Self.response(status: "success", checkpoint: "42"))

        let result = try await provider.checkStatus(query: Self.query)

        XCTAssertEqual(result.status, .confirmed)
        XCTAssertEqual(result.blockNumber, 42)
    }

    func testFailedEffectsMapToFailed() async throws {
        let provider = makeProvider()
        http.queueDecoded(Self.response(status: "failure"))

        let result = try await provider.checkStatus(query: Self.query)

        XCTAssertEqual(result.status, .failed(reason: "Transaction failed"))
    }

    func testUnknownDigestMapsToNotFound() async throws {
        let provider = makeProvider()
        http.queueDecoded(SuiTransactionStatusResponse(
            jsonrpc: "2.0",
            id: 1,
            result: nil,
            error: SuiTransactionStatusResponse.SuiError(code: -32602, message: "not found")
        ))

        let result = try await provider.checkStatus(query: Self.query)

        XCTAssertEqual(result.status, .notFound)
    }

    // MARK: - Helpers

    private func makeProvider() -> SuiTransactionStatusProvider {
        SuiTransactionStatusProvider(httpClient: http, resolver: FixedSuiResolver(url: nil))
    }

    private static func response(
        status: String,
        checkpoint: String? = nil
    ) -> SuiTransactionStatusResponse {
        SuiTransactionStatusResponse(
            jsonrpc: "2.0",
            id: 1,
            result: SuiTransactionStatusResponse.SuiTxResult(
                effects: SuiTransactionStatusResponse.SuiEffects(
                    status: SuiTransactionStatusResponse.SuiStatus(status: status)
                ),
                checkpoint: checkpoint
            ),
            error: nil
        )
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

/// Records the URL of every request so a test can assert which host was hit,
/// and replays queued decoded values through the typed overload.
private final class RecordingHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    private enum Queued {
        case value(Any)
        case error(Error)
    }

    private let lock = NSLock()
    private var queue: [Queued] = []
    private var recorded: [URL] = []

    var requestedURLs: [URL] {
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
        // The provider only uses the typed overload; this path should not run.
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
