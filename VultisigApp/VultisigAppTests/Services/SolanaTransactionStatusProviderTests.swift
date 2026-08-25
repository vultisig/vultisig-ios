//
//  SolanaTransactionStatusProviderTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class SolanaTransactionStatusProviderTests: XCTestCase {

    private static let query = TransactionStatusQuery(txHash: "signature", chain: .solana)

    func testConfirmedObjectErrorReturnsFailed() async throws {
        let result = try await checkStatus(
            status: "confirmed",
            errorJSON: #"{"InstructionError":[0,{"Custom":6001}]}"#
        )

        XCTAssertEqual(result.status, .failed(reason: "transactionFailed".localized))
    }

    func testProcessedStringErrorReturnsFailed() async throws {
        let result = try await checkStatus(
            status: "processed",
            errorJSON: #""AccountInUse""#
        )

        XCTAssertEqual(result.status, .failed(reason: "transactionFailed".localized))
    }

    func testErrorWithoutConfirmationStatusReturnsFailed() async throws {
        let result = try await checkStatus(
            status: nil,
            errorJSON: #""BlockhashNotFound""#
        )

        XCTAssertEqual(result.status, .failed(reason: "transactionFailed".localized))
    }

    func testConfirmedWithoutErrorReturnsConfirmed() async throws {
        let result = try await checkStatus(status: "confirmed")

        XCTAssertEqual(result.status, .confirmed)
        XCTAssertEqual(result.blockNumber, 42)
    }

    func testFinalizedWithoutErrorReturnsConfirmed() async throws {
        let result = try await checkStatus(status: "finalized")

        XCTAssertEqual(result.status, .confirmed)
        XCTAssertEqual(result.blockNumber, 42)
    }

    func testProcessedWithoutErrorReturnsPending() async throws {
        let result = try await checkStatus(status: "processed")

        XCTAssertEqual(result.status, .pending)
    }

    func testKnownSignatureWithoutConfirmationStatusReturnsPending() async throws {
        let result = try await checkStatus(status: nil)

        XCTAssertEqual(result.status, .pending)
    }

    func testNullSignatureReturnsNotFound() async throws {
        let client = SolanaStatusHTTPClient(json: #"{"result":{"value":[null]}}"#)
        let provider = SolanaTransactionStatusProvider(httpClient: client)

        let result = try await provider.checkStatus(query: Self.query)

        XCTAssertEqual(result.status, .notFound)
    }

    private func checkStatus(
        status: String?,
        errorJSON: String = "null"
    ) async throws -> TransactionStatusResult {
        let statusJSON = status.map { #""\#($0)""# } ?? "null"
        let json = #"{"result":{"value":[{"slot":42,"err":\#(errorJSON),"confirmationStatus":\#(statusJSON)}]}}"#
        let client = SolanaStatusHTTPClient(json: json)
        let provider = SolanaTransactionStatusProvider(httpClient: client)

        return try await provider.checkStatus(query: Self.query)
    }
}

private final class SolanaStatusHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private let data: Data

    init(json: String) {
        self.data = Data(json.utf8)
    }

    // swiftlint:disable:next async_without_await
    func request(_: TargetType) async throws -> HTTPResponse<Data> {
        let response = HTTPURLResponse(
            url: URL(string: "https://test.local")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return HTTPResponse(data: data, response: response)
    }
}
