//
//  SolanaServiceBroadcastTests.swift
//  VultisigAppTests
//
//  Covers the Solana client-side rebroadcast loop in
//  `SolanaService.sendSolanaTransaction`. The loop resends the same signed tx
//  on a transient "blockhash not found" (the receiving RPC node hasn't yet
//  observed our `confirmed` blockhash) but escalates a true expiry
//  ("block height exceeded") as a retryable error so the keysign ceremony
//  re-signs with a fresh blockhash.
//

@testable import VultisigApp
import XCTest

final class SolanaServiceBroadcastTests: XCTestCase {

    private func makeService(_ stub: SolanaStubHTTPClient) -> SolanaService {
        SolanaService(
            resolver: NoOverrideResolver(),
            httpClient: stub,
            broadcastRetryBackoff: .zero
        )
    }

    func test_send_returnsSignature_onFirstAttempt() async throws {
        let stub = SolanaStubHTTPClient(results: [.success("sig123")])
        let service = makeService(stub)

        let txid = try await service.sendSolanaTransaction(encodedTransaction: "tx")

        XCTAssertEqual(txid, "sig123")
        XCTAssertEqual(stub.callCount, 1)
    }

    func test_send_resendsOnTransientBlockhashNotFound_thenSucceeds() async throws {
        let stub = SolanaStubHTTPClient(results: [
            .error(code: -32002, message: "Transaction simulation failed: Blockhash not found"),
            .success("sigRetry")
        ])
        let service = makeService(stub)

        let txid = try await service.sendSolanaTransaction(encodedTransaction: "tx")

        XCTAssertEqual(txid, "sigRetry")
        XCTAssertEqual(stub.callCount, 2)
    }

    func test_send_exhaustsBlockhashNotFound_throwsRetryable() async {
        let stub = SolanaStubHTTPClient(results: [
            .error(code: -32002, message: "Blockhash not found"),
            .error(code: -32002, message: "Blockhash not found"),
            .error(code: -32002, message: "Blockhash not found")
        ])
        let service = makeService(stub)

        do {
            _ = try await service.sendSolanaTransaction(encodedTransaction: "tx")
            XCTFail("expected blockhashExpired to be thrown")
        } catch let error as SolanaRetryableError {
            guard case .blockhashExpired = error else {
                return XCTFail("unexpected retryable case: \(error)")
            }
            XCTAssertEqual(error.retryReason, .staleBlockhash)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(stub.callCount, 3)
    }

    func test_send_blockHeightExceeded_throwsRetryableWithoutResending() async {
        let stub = SolanaStubHTTPClient(results: [
            .error(code: -32002, message: "Transaction's block height exceeded the last valid block height")
        ])
        let service = makeService(stub)

        do {
            _ = try await service.sendSolanaTransaction(encodedTransaction: "tx")
            XCTFail("expected blockhashExpired to be thrown")
        } catch let error as SolanaRetryableError {
            guard case .blockhashExpired = error else {
                return XCTFail("unexpected retryable case: \(error)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        // True expiry must not be retried — resending the same tx can't help.
        XCTAssertEqual(stub.callCount, 1)
    }

    func test_send_genericRpcError_throwsImmediately() async {
        let stub = SolanaStubHTTPClient(results: [
            .error(code: -32003, message: "Transaction signature verification failure")
        ])
        let service = makeService(stub)

        do {
            _ = try await service.sendSolanaTransaction(encodedTransaction: "tx")
            XCTFail("expected rpcError to be thrown")
        } catch let error as SolanaServiceError {
            guard case .rpcError(_, let code) = error else {
                return XCTFail("unexpected service error: \(error)")
            }
            XCTAssertEqual(code, -32003)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(stub.callCount, 1)
    }
}

// MARK: - Test doubles

private struct NoOverrideResolver: RPCEndpointResolving {
    // swiftlint:disable:next unused_parameter
    func url(for chain: Chain) -> String? { nil }
}

/// Replays a scripted sequence of JSON-RPC `sendTransaction` outcomes, one per
/// call, so the rebroadcast loop can be exercised deterministically.
private final class SolanaStubHTTPClient: HTTPClientProtocol {

    enum Outcome {
        case success(String)
        case error(code: Int, message: String)
    }

    private let results: [Outcome]
    private(set) var callCount = 0

    init(results: [Outcome]) {
        self.results = results
    }

    // Protocol requires `async`; the body is sync. Silence the lint here.
    // swiftlint:disable:next async_without_await unused_parameter
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        defer { callCount += 1 }
        guard callCount < results.count else {
            XCTFail("SolanaStubHTTPClient ran out of scripted results (call #\(callCount + 1))")
            throw HTTPError.invalidResponse
        }

        let json: String
        switch results[callCount] {
        case .success(let signature):
            json = #"{"jsonrpc":"2.0","id":1,"result":"\#(signature)"}"#
        case .error(let code, let message):
            json = #"{"jsonrpc":"2.0","id":1,"error":{"code":\#(code),"message":"\#(message)"}}"#
        }

        let response = HTTPURLResponse(
            url: URL(string: "https://test.local")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return HTTPResponse(data: Data(json.utf8), response: response)
    }
}
