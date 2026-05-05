//
//  TonTransactionStatusProviderTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

/// Locks the TON status logic against the SDK / Windows resolver
/// (`vultisig-sdk/packages/core/chain/tx/status/resolvers/ton.ts`):
/// `aborted` and non-zero compute-phase exit codes both fail; nil description
/// stays in pending.
final class TonTransactionStatusProviderTests: XCTestCase {

    private var http: StubHTTPClient!
    private var provider: TonTransactionStatusProvider!

    override func setUp() {
        super.setUp()
        http = StubHTTPClient()
        provider = TonTransactionStatusProvider(httpClient: http)
    }

    override func tearDown() {
        http = nil
        provider = nil
        super.tearDown()
    }

    // MARK: - Not-found / pending paths

    func test_checkStatus_emptyTransactions_returnsNotFound() async throws {
        http.queueDecoded(TonTransactionStatusResponse(transactions: []))
        let result = try await provider.checkStatus(query: Self.query)
        XCTAssertEqual(result.status, .notFound)
    }

    func test_checkStatus_nilTransactions_returnsNotFound() async throws {
        http.queueDecoded(TonTransactionStatusResponse(transactions: nil))
        let result = try await provider.checkStatus(query: Self.query)
        XCTAssertEqual(result.status, .notFound)
    }

    func test_checkStatus_descriptionMissing_returnsNotFound() async throws {
        // TON Center sometimes returns a tx record before populating
        // execution details. Don't declare success until description lands.
        http.queueDecoded(Self.response(description: nil))
        let result = try await provider.checkStatus(query: Self.query)
        XCTAssertEqual(result.status, .notFound)
    }

    func test_checkStatus_404_returnsNotFound() async throws {
        http.queueError(HTTPError.statusCode(404, Data()))
        let result = try await provider.checkStatus(query: Self.query)
        XCTAssertEqual(result.status, .notFound)
    }

    // MARK: - Failure paths

    func test_checkStatus_aborted_returnsFailed() async throws {
        http.queueDecoded(Self.response(aborted: true))
        let result = try await provider.checkStatus(query: Self.query)
        XCTAssertEqual(result.status, .failed(reason: "Transaction aborted"))
    }

    func test_checkStatus_nonZeroExitCode_returnsFailedWithCode() async throws {
        http.queueDecoded(Self.response(exitCode: 33))
        let result = try await provider.checkStatus(query: Self.query)
        XCTAssertEqual(result.status, .failed(reason: "Compute phase exited with code 33"))
    }

    func test_checkStatus_abortedWinsOverExitCode() async throws {
        // If both signals fire, abort takes precedence — matches SDK ordering.
        http.queueDecoded(Self.response(aborted: true, exitCode: 33))
        let result = try await provider.checkStatus(query: Self.query)
        XCTAssertEqual(result.status, .failed(reason: "Transaction aborted"))
    }

    // MARK: - Success paths

    func test_checkStatus_exitCodeZero_returnsConfirmed() async throws {
        http.queueDecoded(Self.response(exitCode: 0))
        let result = try await provider.checkStatus(query: Self.query)
        XCTAssertEqual(result.status, .confirmed)
    }

    func test_checkStatus_exitCodeOne_returnsConfirmed() async throws {
        // TVM convention: 1 is the "alternative success" code used by some checks.
        http.queueDecoded(Self.response(exitCode: 1))
        let result = try await provider.checkStatus(query: Self.query)
        XCTAssertEqual(result.status, .confirmed)
    }

    func test_checkStatus_noComputePhase_returnsConfirmed() async throws {
        // Plain TON transfers have no compute phase — treat as confirmed.
        http.queueDecoded(Self.response(aborted: false, exitCode: nil))
        let result = try await provider.checkStatus(query: Self.query)
        XCTAssertEqual(result.status, .confirmed)
    }

    // MARK: - Network errors

    func test_checkStatus_non404HTTPError_rethrows() async {
        http.queueError(HTTPError.statusCode(503, Data()))
        do {
            _ = try await provider.checkStatus(query: Self.query)
            XCTFail("Expected non-404 HTTPError to propagate")
        } catch let error as HTTPError {
            if case .statusCode(let code, _) = error {
                XCTAssertEqual(code, 503)
            } else {
                XCTFail("Unexpected HTTPError variant: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Fixtures

    private static let query = TransactionStatusQuery(txHash: "deadbeef", chain: .ton)

    private static func response(
        aborted: Bool? = nil,
        exitCode: Int? = nil
    ) -> TonTransactionStatusResponse {
        let computePhase: TonTransactionStatusResponse.TonTransaction.TonDescription.ComputePhase?
        if let exitCode {
            computePhase = .init(exitCode: exitCode)
        } else {
            computePhase = nil
        }
        let description = TonTransactionStatusResponse.TonTransaction.TonDescription(
            aborted: aborted,
            destroyed: nil,
            computePhase: computePhase
        )
        return response(description: description)
    }

    private static func response(
        description: TonTransactionStatusResponse.TonTransaction.TonDescription?
    ) -> TonTransactionStatusResponse {
        let tx = TonTransactionStatusResponse.TonTransaction(
            account: nil,
            hash: "txhash",
            lt: "12345",
            now: nil,
            origStatus: nil,
            endStatus: nil,
            totalFees: nil,
            data: nil,
            description: description
        )
        return TonTransactionStatusResponse(transactions: [tx])
    }
}

// MARK: - Test double

/// Minimal stub conforming to `HTTPClientProtocol`. Tests queue either a
/// pre-built decoded value (returned via the typed `request<T>` overload) or
/// an error.
private final class StubHTTPClient: HTTPClientProtocol {

    private enum Queued {
        case value(Any)
        case error(Error)
    }

    private var pending: Queued?

    func queueDecoded<T>(_ value: T) {
        pending = .value(value)
    }

    func queueError(_ error: Error) {
        pending = .error(error)
    }

    // Protocol requires `async`; the body is sync. SwiftLint can't see across
    // protocol conformance, so silence the false-positive lint here.
    // swiftlint:disable async_without_await
    func request(_: TargetType) async throws -> HTTPResponse<Data> {
        // The provider only uses the typed overload; this path should not run.
        throw HTTPError.invalidResponse
    }

    func request<T: Decodable>(
        _: TargetType,
        responseType _: T.Type
    ) async throws -> HTTPResponse<T> {
        guard let pending else {
            XCTFail("StubHTTPClient called with no queued response")
            throw HTTPError.invalidResponse
        }
        self.pending = nil

        switch pending {
        case .error(let error):
            throw error
        case .value(let raw):
            guard let typed = raw as? T else {
                XCTFail("Queued value type \(type(of: raw)) does not match \(T.self)")
                throw HTTPError.invalidResponse
            }
            let stub = HTTPURLResponse(
                url: URL(string: "https://test.local")!,
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
