//
//  RippleBroadcastGatingTests.swift
//  VultisigAppTests
//
//  Service-level tests for the XRPL broadcast gate: `broadcastTransaction`
//  returns the echoed deterministic hash only when the submit is accepted,
//  and throws `RippleBroadcastError.broadcastFailed` carrying the real
//  engine code (the string the keysign error screen renders) otherwise.
//

@testable import VultisigApp
import XCTest

final class RippleBroadcastGatingTests: XCTestCase {

    private static let txHash = "E08D6E9754025BA2534A78707605E0601F03ACE063687A0CA1BDDACFCD1698C7"
    private static let txBlob = "DEADBEEF"

    func testBroadcastReturnsHashOnTesSuccess() async throws {
        let client = RippleStubHTTPClient()
        client.submitJSON = Self.submitJSON(engineResult: "tesSUCCESS", hash: Self.txHash)
        let service = RippleService(httpClient: client)

        let hash = try await service.broadcastTransaction(Self.txBlob)

        XCTAssertEqual(hash, Self.txHash)
        XCTAssertEqual(client.submitCallCount, 1)
    }

    func testBroadcastReturnsHashWhenEngineResultMissing() async throws {
        // Defensive default shared with the SDK resolver: a response without
        // an engine result but with the echoed hash must not brick broadcast.
        let client = RippleStubHTTPClient()
        client.submitJSON = Self.submitJSON(engineResult: nil, hash: Self.txHash)
        let service = RippleService(httpClient: client)

        let hash = try await service.broadcastTransaction(Self.txBlob)

        XCTAssertEqual(hash, Self.txHash)
    }

    func testBroadcastThrowsRippleBroadcastErrorWithCodeOnRejection() async {
        let client = RippleStubHTTPClient()
        client.submitJSON = Self.submitJSON(
            engineResult: "temREDUNDANT",
            engineResultMessage: "The transaction is redundant.",
            hash: Self.txHash
        )
        let service = RippleService(httpClient: client)

        do {
            _ = try await service.broadcastTransaction(Self.txBlob)
            XCTFail("Expected broadcast to throw on temREDUNDANT")
        } catch let error as RippleBroadcastError {
            // `localizedDescription` is the string the keysign error screen
            // ultimately renders — it must carry the real engine code.
            XCTAssertTrue(error.localizedDescription.contains("temREDUNDANT"))
            XCTAssertTrue(error.localizedDescription.contains("The transaction is redundant."))
        } catch {
            XCTFail("Expected RippleBroadcastError, got \(error)")
        }
    }

    func testBroadcastThrowsOnTecResult() async {
        let client = RippleStubHTTPClient()
        client.submitJSON = Self.submitJSON(
            engineResult: "tecUNFUNDED_PAYMENT",
            engineResultMessage: "Insufficient XRP balance to send.",
            hash: Self.txHash
        )
        let service = RippleService(httpClient: client)

        do {
            _ = try await service.broadcastTransaction(Self.txBlob)
            XCTFail("Expected broadcast to throw on tecUNFUNDED_PAYMENT")
        } catch let error as RippleBroadcastError {
            XCTAssertTrue(error.localizedDescription.contains("tecUNFUNDED_PAYMENT"))
        } catch {
            XCTFail("Expected RippleBroadcastError, got \(error)")
        }
    }

    func testBroadcastThrowsWhenSuccessResponseHasNoHash() async {
        let client = RippleStubHTTPClient()
        client.submitJSON = Self.submitJSON(engineResult: "tesSUCCESS", hash: nil)
        let service = RippleService(httpClient: client)

        do {
            _ = try await service.broadcastTransaction(Self.txBlob)
            XCTFail("Expected broadcast to throw when there is no hash to track")
        } catch let error as RippleBroadcastError {
            XCTAssertTrue(error.localizedDescription.contains("tesSUCCESS"))
        } catch {
            XCTFail("Expected RippleBroadcastError, got \(error)")
        }
    }

    // MARK: - Fixtures

    static func submitJSON(
        engineResult: String?,
        engineResultMessage: String? = nil,
        hash: String?
    ) -> String {
        var result: [String: Any] = [:]
        if let engineResult {
            result["engine_result"] = engineResult
        }
        if let engineResultMessage {
            result["engine_result_message"] = engineResultMessage
        }
        if let hash {
            result["tx_json"] = ["hash": hash]
        }
        let body: [String: Any] = ["result": result]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let json = String(data: data, encoding: .utf8) else {
            XCTFail("Failed to build submit fixture")
            return "{}"
        }
        return json
    }
}

// MARK: - Test double

/// Stub `HTTPClientProtocol` for `RippleService`. Every XRPL JSON-RPC call
/// posts to `/`, so requests are keyed off the `method` field in the encoded
/// request body rather than the path.
private final class RippleStubHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    enum StubError: Error {
        case unexpectedRequest
    }

    var submitJSON: String = "{}"
    private(set) var submitCallCount = 0

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        await Task.yield()
        switch Self.rpcMethod(of: target) {
        case "submit":
            submitCallCount += 1
            return HTTPResponse(data: Data(submitJSON.utf8), response: Self.ok)
        default:
            throw StubError.unexpectedRequest
        }
    }

    private static func rpcMethod(of target: TargetType) -> String? {
        guard case let .requestCodable(body, _) = target.task,
              let data = try? JSONEncoder().encode(body),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["method"] as? String
    }

    private static let ok = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
}
