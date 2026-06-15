//
//  PolkadotTransactionStatusProviderTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

/// Locks the Polkadot Asset Hub status logic against the node-RPC block scan:
/// the provider walks blocks from the head along `parentHash` and matches the
/// blake2b-256 extrinsic hash. Found in a scanned block → confirmed; not found
/// within the window → pending. Matching is `0x`/case-insensitive.
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
    private static let otherExtrinsic = "0xdeadbeef"

    private static func query(txHash: String) -> TransactionStatusQuery {
        TransactionStatusQuery(txHash: txHash, chain: .polkadot)
    }

    private static func block(extrinsics: [String], parentHash: String) -> PolkadotTransactionStatusResponse {
        PolkadotTransactionStatusResponse(
            result: .init(block: .init(header: .init(parentHash: parentHash), extrinsics: extrinsics)),
            error: nil
        )
    }

    /// `chain_getBlock` returning a null result — the node has no block for the
    /// requested hash, which ends the backward walk.
    private static func emptyBlock() -> PolkadotTransactionStatusResponse {
        PolkadotTransactionStatusResponse(result: nil, error: nil)
    }

    // MARK: - Confirmed (extrinsic found in a scanned block)

    func test_checkStatus_extrinsicInHeadBlock_returnsConfirmed() async throws {
        http.queue(Self.block(extrinsics: [Self.extrinsicHex], parentHash: "0xparent"))
        let result = try await provider.checkStatus(query: Self.query(txHash: Self.extrinsicHash))
        XCTAssertEqual(result.status, .confirmed)
    }

    func test_checkStatus_extrinsicInParentBlock_returnsConfirmed() async throws {
        // Head block doesn't contain it; the walk follows parentHash and finds it.
        http.queue(Self.block(extrinsics: [Self.otherExtrinsic], parentHash: "0xparent1"))
        http.queue(Self.block(extrinsics: [Self.extrinsicHex], parentHash: "0xparent2"))
        let result = try await provider.checkStatus(query: Self.query(txHash: Self.extrinsicHash))
        XCTAssertEqual(result.status, .confirmed)
    }

    func test_checkStatus_matchIsPrefixAndCaseInsensitive() async throws {
        http.queue(Self.block(extrinsics: [Self.extrinsicHex], parentHash: "0xparent"))
        let noPrefixUpper = Self.extrinsicHash.stripHexPrefix().uppercased()
        let result = try await provider.checkStatus(query: Self.query(txHash: noPrefixUpper))
        XCTAssertEqual(result.status, .confirmed)
    }

    // MARK: - Pending (not found within the scanned window)

    func test_checkStatus_notFoundBeforeWalkEnds_returnsPending() async throws {
        // One block without the extrinsic, then the walk hits a null block (end).
        http.queue(Self.block(extrinsics: [Self.otherExtrinsic], parentHash: "0xparent1"))
        http.queue(Self.emptyBlock())
        let result = try await provider.checkStatus(query: Self.query(txHash: Self.extrinsicHash))
        XCTAssertEqual(result.status, .pending)
    }

    func test_checkStatus_emptyHash_returnsNotFoundWithoutRequest() async throws {
        let result = try await provider.checkStatus(query: Self.query(txHash: ""))
        XCTAssertEqual(result.status, .notFound)
    }

    // MARK: - RPC error

    func test_checkStatus_rpcError_throws() async {
        http.queue(PolkadotTransactionStatusResponse(result: nil, error: .init(code: -32000, message: "boom")))
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

/// Minimal stub conforming to `HTTPClientProtocol`. Tests queue decoded values
/// (FIFO) returned via the typed `request<T>` overload, since the provider's
/// chain walk issues several `chain_getBlock` calls per check.
private final class StubHTTPClient: HTTPClientProtocol {

    private var pending: [Any] = []

    func queue<T>(_ value: T) {
        pending.append(value)
    }

    // swiftlint:disable async_without_await
    func request(_: TargetType) async throws -> HTTPResponse<Data> {
        throw HTTPError.invalidResponse
    }

    func request<T: Decodable>(
        _: TargetType,
        responseType _: T.Type
    ) async throws -> HTTPResponse<T> {
        guard !pending.isEmpty else {
            XCTFail("StubHTTPClient called with no queued response")
            throw HTTPError.invalidResponse
        }
        let raw = pending.removeFirst()

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

    func requestEmpty(_: TargetType) async throws -> HTTPResponse<EmptyResponse> {
        throw HTTPError.invalidResponse
    }
    // swiftlint:enable async_without_await
}
