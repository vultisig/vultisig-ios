//
//  TronBroadcastHashValidationTests.swift
//  VultisigAppTests
//
//  A TRON txid is `sha256(raw_data)`, which the signer already computed before
//  the transaction left the device. Adopting the value the broadcast endpoint
//  reports instead means the app tracks, displays and links to whatever hash it
//  was handed. These pin the comparison and the hash the caller receives.
//

@testable import VultisigApp
import XCTest

final class TronBroadcastHashValidationTests: XCTestCase {

    private static let localHash = "9f1b5ab2ce1d0b0f4a5e0d3c2b1a09876543210fedcba98765432100abcdef12"

    // MARK: - Comparison

    func testIdenticalHashesMatch() {
        XCTAssertTrue(
            TronAPIService.txidMatchesLocalHash(nodeTxid: Self.localHash, localTxHash: Self.localHash)
        )
    }

    func testComparisonIgnoresCaseAndHexPrefix() {
        XCTAssertTrue(
            TronAPIService.txidMatchesLocalHash(
                nodeTxid: "0x" + Self.localHash.uppercased(),
                localTxHash: Self.localHash
            )
        )
    }

    func testDifferentHashesDoNotMatch() {
        XCTAssertFalse(
            TronAPIService.txidMatchesLocalHash(
                nodeTxid: String(Self.localHash.dropLast()) + "3",
                localTxHash: Self.localHash
            )
        )
    }

    /// Without a locally computed hash there is nothing to verify against, and
    /// falling back to the node's value is what this check exists to prevent.
    func testEmptyLocalHashNeverMatches() {
        XCTAssertFalse(
            TronAPIService.txidMatchesLocalHash(nodeTxid: Self.localHash, localTxHash: "")
        )
        XCTAssertFalse(TronAPIService.txidMatchesLocalHash(nodeTxid: "", localTxHash: ""))
    }

    // MARK: - Broadcast

    func testBroadcastReturnsTheLocallyComputedHash() async throws {
        let service = makeService(json: """
        {"result":true,"txid":"\(Self.localHash.uppercased())"}
        """)

        let txHash = try await service.broadcastTransaction(
            jsonString: "{}",
            expectedTxHash: Self.localHash
        )

        XCTAssertEqual(txHash, Self.localHash)
    }

    func testBroadcastRejectsAMismatchedTxid() async {
        let service = makeService(json: """
        {"result":true,"txid":"00000000000000000000000000000000000000000000000000000000deadbeef"}
        """)

        do {
            _ = try await service.broadcastTransaction(jsonString: "{}", expectedTxHash: Self.localHash)
            XCTFail("expected a hash mismatch to throw")
        } catch let error as TronAPIError {
            guard case .broadcastHashMismatch = error else {
                return XCTFail("expected broadcastHashMismatch, got \(error)")
            }
        } catch {
            XCTFail("expected TronAPIError, got \(error)")
        }
    }

    /// A duplicate broadcast is still treated as success, and still has to
    /// describe the transaction this device signed.
    func testDuplicateBroadcastStillValidatesTheTxid() async throws {
        let service = makeService(json: """
        {"code":"DUP_TRANSACTION_ERROR","txid":"\(Self.localHash)"}
        """)

        let txHash = try await service.broadcastTransaction(
            jsonString: "{}",
            expectedTxHash: Self.localHash
        )

        XCTAssertEqual(txHash, Self.localHash)
    }

    /// A rejected broadcast still reports the node's error rather than a hash
    /// mismatch — the mismatch check must not mask why the send failed.
    func testRejectedBroadcastReportsTheNodeError() async {
        let service = makeService(json: """
        {"result":false,"code":"SIGERROR","message":"bad signature","txid":"\(Self.localHash)"}
        """)

        do {
            _ = try await service.broadcastTransaction(jsonString: "{}", expectedTxHash: Self.localHash)
            XCTFail("expected a rejected broadcast to throw")
        } catch let error as TronAPIError {
            guard case .broadcastFailed(let message) = error else {
                return XCTFail("expected broadcastFailed, got \(error)")
            }
            XCTAssertEqual(message, "bad signature")
        } catch {
            XCTFail("expected TronAPIError, got \(error)")
        }
    }

    private func makeService(json: String) -> TronAPIService {
        TronAPIService(
            httpClient: TronBroadcastStubHTTPClient(json: json),
            resolver: NoOverrideResolver()
        )
    }
}

private struct NoOverrideResolver: RPCEndpointResolving {
    func url(for _: Chain) -> String? { nil }
}

private final class TronBroadcastStubHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private let json: String

    init(json: String) {
        self.json = json
    }

    // The asynchronous signatures are protocol requirements; this in-memory
    // test double intentionally does not suspend.
    // swiftlint:disable async_without_await
    func request(_: TargetType) async throws -> HTTPResponse<Data> {
        throw HTTPError.invalidResponse
    }

    func request<T: Decodable>(
        _: TargetType,
        responseType _: T.Type
    ) async throws -> HTTPResponse<T> {
        let decoded = try JSONDecoder().decode(T.self, from: Data(json.utf8))
        let urlResponse = HTTPURLResponse(
            url: URL(string: "https://test.local")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return HTTPResponse(data: decoded, response: urlResponse)
    }

    func requestEmpty(_: TargetType) async throws -> HTTPResponse<EmptyResponse> {
        throw HTTPError.invalidResponse
    }
    // swiftlint:enable async_without_await
}
