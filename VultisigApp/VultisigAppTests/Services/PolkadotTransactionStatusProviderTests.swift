//
//  PolkadotTransactionStatusProviderTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

/// Locks the Polkadot Asset Hub status logic against the node-RPC
/// `author_pendingExtrinsics` pool check: an extrinsic still in the pool is
/// pending, one that has left the pool is treated as confirmed. The match keys
/// off blake2b-256 of the extrinsic bytes and is `0x`/case-insensitive.
final class PolkadotTransactionStatusProviderTests: XCTestCase {

    private var http: StubHTTPClient!
    private var provider: PolkadotTransactionStatusProvider!

    override func setUp() {
        super.setUp()
        http = StubHTTPClient()
        provider = PolkadotTransactionStatusProvider(httpClient: http)
    }

    override func tearDown() {
        http = nil
        provider = nil
        super.tearDown()
    }

    // Extrinsic bytes 0x0a0b0c0d and its blake2b-256 (the value the node returns
    // as the extrinsic hash from `author_submitExtrinsic`).
    private static let extrinsicHex = "0x0a0b0c0d"
    private static let extrinsicHash = "0xcff0a3a65280d9d25957db5bf48473ccc86a6ddfb1492797ac6c8f8de635e72a"

    private static func query(txHash: String) -> TransactionStatusQuery {
        TransactionStatusQuery(txHash: txHash, chain: .polkadot)
    }

    // MARK: - Pending (still in the pool)

    func test_checkStatus_hashInPool_returnsPending() async throws {
        http.queueDecoded(PolkadotTransactionStatusResponse(result: [Self.extrinsicHex], error: nil))
        let result = try await provider.checkStatus(query: Self.query(txHash: Self.extrinsicHash))
        XCTAssertEqual(result.status, .pending)
    }

    func test_checkStatus_hashInPool_isPrefixAndCaseInsensitive() async throws {
        http.queueDecoded(PolkadotTransactionStatusResponse(result: [Self.extrinsicHex], error: nil))
        let noPrefixUpper = Self.extrinsicHash.stripHexPrefix().uppercased()
        let result = try await provider.checkStatus(query: Self.query(txHash: noPrefixUpper))
        XCTAssertEqual(result.status, .pending)
    }

    // MARK: - Confirmed (left the pool)

    func test_checkStatus_hashNotInPool_returnsConfirmed() async throws {
        http.queueDecoded(PolkadotTransactionStatusResponse(result: ["0xdeadbeef"], error: nil))
        let result = try await provider.checkStatus(query: Self.query(txHash: Self.extrinsicHash))
        XCTAssertEqual(result.status, .confirmed)
    }

    func test_checkStatus_emptyPool_returnsConfirmed() async throws {
        http.queueDecoded(PolkadotTransactionStatusResponse(result: [], error: nil))
        let result = try await provider.checkStatus(query: Self.query(txHash: Self.extrinsicHash))
        XCTAssertEqual(result.status, .confirmed)
    }

    func test_checkStatus_nilResult_returnsConfirmed() async throws {
        http.queueDecoded(PolkadotTransactionStatusResponse(result: nil, error: nil))
        let result = try await provider.checkStatus(query: Self.query(txHash: Self.extrinsicHash))
        XCTAssertEqual(result.status, .confirmed)
    }

    // MARK: - RPC error

    func test_checkStatus_rpcError_throws() async {
        http.queueDecoded(PolkadotTransactionStatusResponse(
            result: nil,
            error: .init(code: -32000, message: "boom")
        ))
        do {
            _ = try await provider.checkStatus(query: Self.query(txHash: Self.extrinsicHash))
            XCTFail("Expected RPC error to propagate")
        } catch let error as RpcServiceError {
            if case .rpcError(let code, _) = error {
                XCTAssertEqual(code, -32000)
            } else {
                XCTFail("Unexpected RpcServiceError variant: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Test double

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

    // swiftlint:disable async_without_await
    func request(_: TargetType) async throws -> HTTPResponse<Data> {
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
