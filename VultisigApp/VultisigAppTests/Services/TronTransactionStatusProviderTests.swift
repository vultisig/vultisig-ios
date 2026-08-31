//
//  TronTransactionStatusProviderTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class TronTransactionStatusProviderTests: XCTestCase {
    private static let query = TransactionStatusQuery(txHash: "deadbeef", chain: .tron)

    func testSuccessReceiptIsConfirmed() async throws {
        let result = try await checkStatus(
            response(id: "deadbeef", blockNumber: 123, receiptResult: "SUCCESS")
        )

        XCTAssertEqual(result.status, .confirmed)
        XCTAssertEqual(result.blockNumber, 123)
    }

    func testLowercaseSuccessReceiptIsConfirmed() async throws {
        let result = try await checkStatus(
            response(id: "deadbeef", blockNumber: 123, receiptResult: "success")
        )

        XCTAssertEqual(result.status, .confirmed)
    }

    func testNilReceiptResultIsConfirmed() async throws {
        let result = try await checkStatus(
            response(id: "deadbeef", blockNumber: 123, receiptResult: nil)
        )

        XCTAssertEqual(result.status, .confirmed)
    }

    func testFailureReceiptResultIncludesResponseMessage() async throws {
        let result = try await checkStatus(
            response(
                id: "deadbeef",
                blockNumber: 123,
                receiptResult: "OUT_OF_ENERGY",
                resMessage: "Not enough energy"
            )
        )

        XCTAssertEqual(result.status, .failed(reason: "OUT_OF_ENERGY: Not enough energy"))
    }

    func testEmptyReceiptResultIsFailed() async throws {
        let result = try await checkStatus(
            response(id: "deadbeef", blockNumber: 123, receiptResult: "")
        )

        XCTAssertEqual(result.status, .failed(reason: ""))
    }

    func testUnknownReceiptResultIsFailed() async throws {
        let result = try await checkStatus(
            response(id: "deadbeef", blockNumber: 123, receiptResult: "UNKNOWN_FUTURE_CODE")
        )

        XCTAssertEqual(result.status, .failed(reason: "UNKNOWN_FUTURE_CODE"))
    }

    func testTopLevelFailureWinsOverSuccessfulReceipt() async throws {
        let result = try await checkStatus(
            response(
                id: "deadbeef",
                blockNumber: 123,
                receiptResult: "SUCCESS",
                result: "FAILED",
                resMessage: "Validation failed"
            )
        )

        XCTAssertEqual(result.status, .failed(reason: "Validation failed"))
    }

    func testMissingReceiptIsPending() async throws {
        let result = try await checkStatus(
            response(id: "deadbeef", blockNumber: 123, hasReceipt: false)
        )

        XCTAssertEqual(result.status, .pending)
        XCTAssertEqual(result.blockNumber, 123)
    }

    func testMissingTransactionIdIsNotFound() async throws {
        let result = try await checkStatus(
            response(id: nil, blockNumber: nil, hasReceipt: false)
        )

        XCTAssertEqual(result.status, .notFound)
        XCTAssertNil(result.blockNumber)
    }

    private func checkStatus(
        _ response: TronTransactionStatusResponse
    ) async throws -> TransactionStatusResult {
        let client = TronTransactionStatusHTTPClient(response: response)
        let provider = TronTransactionStatusProvider(httpClient: client)
        return try await provider.checkStatus(query: Self.query)
    }

    private func response(
        id: String?,
        blockNumber: Int?,
        receiptResult: String? = nil,
        hasReceipt: Bool = true,
        result: String? = nil,
        resMessage: String? = nil
    ) -> TronTransactionStatusResponse {
        let receipt = hasReceipt
            ? TronTransactionStatusResponse.TronReceipt(
                result: receiptResult,
                net_fee: nil,
                energy_fee: nil,
                energy_usage_total: nil
            )
            : nil

        return TronTransactionStatusResponse(
            id: id,
            blockNumber: blockNumber,
            blockTimeStamp: nil,
            fee: nil,
            receipt: receipt,
            result: result,
            resMessage: resMessage
        )
    }
}

private final class TronTransactionStatusHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private let response: TronTransactionStatusResponse

    init(response: TronTransactionStatusResponse) {
        self.response = response
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
        guard let typedResponse = response as? T else {
            throw HTTPError.invalidResponse
        }

        let urlResponse = HTTPURLResponse(
            url: URL(string: "https://test.local")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return HTTPResponse(data: typedResponse, response: urlResponse)
    }

    func requestEmpty(_: TargetType) async throws -> HTTPResponse<EmptyResponse> {
        throw HTTPError.invalidResponse
    }
    // swiftlint:enable async_without_await
}
