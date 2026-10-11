//
//  CardanoBroadcastTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class CardanoBroadcastTests: XCTestCase {

    private static let precomputedTxId = "precomputed-tx-id"

    private static let alreadyIncludedBody = """
    {"jsonrpc":"2.0","method":"submitTransaction","error":{"code":3997,\
    "message":"The transaction couldn't be added to the mempool. A justification is given as 'data.error'.",\
    "data":{"error":"All inputs are spent. Transaction has probably already been included"}},"id":1}
    """

    private static let unknownInputsBody = """
    {"jsonrpc":"2.0","method":"submitTransaction","error":{"code":3117,\
    "message":"The transaction contains unknown UTxO references as inputs.",\
    "data":{"unknownOutputReferences":[{"transaction":{"id":"aa"},"index":0}]}},"id":1}
    """

    private static let genuineFailureBody = """
    {"jsonrpc":"2.0","method":"submitTransaction","error":{"code":3997,\
    "message":"The transaction couldn't be added to the mempool. A justification is given as 'data.error'.",\
    "data":{"error":"Unelected committee voters"}},"id":1}
    """

    private static let successBody = """
    {"jsonrpc":"2.0","method":"submitTransaction","result":{"transaction":{"id":"node-tx-id"}},"id":1}
    """

    func testAlreadyIncludedReplyReturnsPrecomputedHash() async throws {
        let txId = try await broadcast(Self.alreadyIncludedBody, status: 400)
        XCTAssertEqual(txId, Self.precomputedTxId)
    }

    func testUnknownInputsReplyReturnsPrecomputedHash() async throws {
        let txId = try await broadcast(Self.unknownInputsBody, status: 400)
        XCTAssertEqual(txId, Self.precomputedTxId)
    }

    func testGenuineMempoolRejectionStillThrowsWithJustification() async {
        do {
            _ = try await broadcast(Self.genuineFailureBody, status: 400)
            XCTFail("Expected the broadcast to throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "RPC Error: Unelected committee voters")
        }
    }

    func testAlreadyIncludedTextUnderAnotherCodeStillThrows() async {
        let body = Self.alreadyIncludedBody.replacingOccurrences(of: "3997", with: "3000")
        do {
            _ = try await broadcast(body, status: 400)
            XCTFail("Expected the broadcast to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.hasPrefix("RPC Error:"))
        }
    }

    func testPartialSpendJustificationStillThrows() async {
        let body = Self.alreadyIncludedBody.replacingOccurrences(
            of: "All inputs are spent. Transaction has probably already been included",
            with: "Not all inputs are spent"
        )
        do {
            _ = try await broadcast(body, status: 400)
            XCTFail("Expected the broadcast to throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "RPC Error: Not all inputs are spent")
        }
    }

    func testNegatedIncludedJustificationStillThrows() async {
        let body = Self.alreadyIncludedBody.replacingOccurrences(
            of: "All inputs are spent. Transaction has probably already been included",
            with: "Transaction has not already been included"
        )
        do {
            _ = try await broadcast(body, status: 400)
            XCTFail("Expected the broadcast to throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "RPC Error: Transaction has not already been included")
        }
    }

    func testAcceptedReplyReturnsNodeHash() async throws {
        let txId = try await broadcast(Self.successBody, status: 200)
        XCTAssertEqual(txId, "node-tx-id")
    }

    private func broadcast(_ body: String, status: Int) async throws -> String {
        let service = CardanoService(httpClient: CardanoStubHTTPClient(body: body, status: status))
        return try await service.broadcastTransaction(
            signedTransaction: "84a0",
            precomputedTxId: Self.precomputedTxId
        )
    }
}

private struct CardanoStubHTTPClient: HTTPClientProtocol {
    let body: String
    let status: Int

    // The asynchronous signatures are protocol requirements; this in-memory
    // test double intentionally does not suspend.
    // swiftlint:disable async_without_await
    func request(_: TargetType) async throws -> HTTPResponse<Data> {
        let urlResponse = HTTPURLResponse(
            url: URL(string: "https://test.local")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return HTTPResponse(data: Data(body.utf8), response: urlResponse)
    }
    // swiftlint:enable async_without_await
}
