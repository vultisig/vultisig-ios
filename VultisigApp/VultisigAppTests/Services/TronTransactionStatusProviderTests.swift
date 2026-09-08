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

    // MARK: - Expiration

    /// A TRON transaction carries an `expiration`; once it passes unconfirmed
    /// no block can ever include it. Before this the provider answered
    /// `notFound` and the row stayed in flight on every app open.
    func testUnconfirmedTransactionPastItsExpirationIsExpired() async throws {
        let result = try await checkStatus(
            response(id: nil, blockNumber: nil, hasReceipt: false),
            rawTransactionJSON: Self.rawTransactionJSON(expiration: 1_700_000_000_000),
            nowBlockJSON: Self.nowBlockJSON(timestamp: 1_780_000_000_000)
        )

        XCTAssertEqual(
            result.status,
            .expired(reason: TronTransactionStatusProvider.expiredReason)
        )
    }

    /// A transaction the chain head has not yet passed keeps polling.
    func testUnconfirmedTransactionBeforeItsExpirationKeepsPolling() async throws {
        let result = try await checkStatus(
            response(id: nil, blockNumber: nil, hasReceipt: false),
            rawTransactionJSON: Self.rawTransactionJSON(expiration: 1_700_000_000_000),
            nowBlockJSON: Self.nowBlockJSON(timestamp: 1_699_999_999_999)
        )

        XCTAssertEqual(result.status, .pending)
    }

    /// TRON validates `expiration` against block time, so the device clock is
    /// not evidence in either direction and must not veto the chain. Both of
    /// these use an expiration far ahead of any real device clock: the first
    /// would stay pending forever if a slow clock could gate the check, and the
    /// second would go terminal if a fast one could force it.
    func testChainTimePastExpirationExpiresEvenWhenTheDeviceClockIsBehind() async throws {
        let result = try await checkStatus(
            response(id: nil, blockNumber: nil, hasReceipt: false),
            rawTransactionJSON: Self.rawTransactionJSON(expiration: 4_000_000_000_000),
            nowBlockJSON: Self.nowBlockJSON(timestamp: 4_000_000_000_001)
        )

        XCTAssertEqual(
            result.status,
            .expired(reason: TronTransactionStatusProvider.expiredReason)
        )
    }

    func testChainTimeBeforeExpirationKeepsPollingWhateverTheDeviceClockSays() async throws {
        let result = try await checkStatus(
            response(id: nil, blockNumber: nil, hasReceipt: false),
            rawTransactionJSON: Self.rawTransactionJSON(expiration: 1_780_000_000_000),
            nowBlockJSON: Self.nowBlockJSON(timestamp: 1_770_000_000_000)
        )

        XCTAssertEqual(result.status, .pending)
    }

    /// An unreachable node is not evidence that a transaction expired.
    func testChainTimeLookupFailureKeepsPolling() async throws {
        let result = try await checkStatus(
            response(id: nil, blockNumber: nil, hasReceipt: false),
            rawTransactionJSON: Self.rawTransactionJSON(expiration: 1_700_000_000_000),
            nowBlockJSON: nil
        )

        XCTAssertEqual(result.status, .pending)
    }

    /// The node no longer holds the transaction, so there is no expiration to
    /// read and the answer is the one it was before.
    func testUnknownRawTransactionStaysNotFound() async throws {
        let result = try await checkStatus(
            response(id: nil, blockNumber: nil, hasReceipt: false),
            rawTransactionJSON: "{}",
            nowBlockJSON: Self.nowBlockJSON(timestamp: 1_780_000_000_000)
        )

        XCTAssertEqual(result.status, .notFound)
    }

    /// A raw transaction for some other hash says nothing about this one.
    func testRawTransactionForAnotherHashStaysNotFound() async throws {
        let result = try await checkStatus(
            response(id: nil, blockNumber: nil, hasReceipt: false),
            rawTransactionJSON: """
            {"txID":"feedface","raw_data":{"expiration":1700000000000}}
            """,
            nowBlockJSON: Self.nowBlockJSON(timestamp: 1_780_000_000_000)
        )

        XCTAssertEqual(result.status, .notFound)
    }

    /// A receipt-less transaction the node reports without a block is checked
    /// against its expiration, and stays pending while the deadline stands.
    func testReceiptlessTransactionWithoutABlockStaysPending() async throws {
        let result = try await checkStatus(
            response(id: "deadbeef", blockNumber: 0, hasReceipt: false),
            rawTransactionJSON: Self.rawTransactionJSON(expiration: 1_700_000_000_000),
            nowBlockJSON: nil
        )

        XCTAssertEqual(result.status, .pending)
    }

    /// A block number is evidence of inclusion. Expiring on it would report a
    /// transaction that already landed as terminally failed, and invite the
    /// user to pay twice — worse than the indefinite polling this replaced.
    /// `gettransactionbyid` answers for included transactions too, so the
    /// matching `txID` here proves nothing about confirmation.
    func testIncludedTransactionAwaitingItsReceiptIsNeverExpired() async throws {
        let client = TronTransactionStatusHTTPClient(
            response: response(id: "deadbeef", blockNumber: 123, hasReceipt: false),
            rawTransactionJSON: Self.rawTransactionJSON(expiration: 1_700_000_000_000),
            nowBlockJSON: Self.nowBlockJSON(timestamp: 1_780_000_000_000)
        )

        let result = try await TronTransactionStatusProvider(httpClient: client)
            .checkStatus(query: Self.query)

        XCTAssertEqual(result.status, .pending)
        XCTAssertEqual(result.blockNumber, 123)
        XCTAssertFalse(client.requestedPaths.contains("/wallet/gettransactionbyid"))
    }

    private static func rawTransactionJSON(expiration: Int64) -> String {
        """
        {"txID":"DEADBEEF","raw_data":{"expiration":\(expiration)}}
        """
    }

    private static func nowBlockJSON(timestamp: Int64) -> String {
        """
        {"block_header":{"raw_data":{"timestamp":\(timestamp),"number":1,"version":0,\
        "txTrieRoot":"00","parentHash":"00","witness_address":"00"}}}
        """
    }

    private func checkStatus(
        _ response: TronTransactionStatusResponse,
        rawTransactionJSON: String? = nil,
        nowBlockJSON: String? = nil
    ) async throws -> TransactionStatusResult {
        let client = TronTransactionStatusHTTPClient(
            response: response,
            rawTransactionJSON: rawTransactionJSON,
            nowBlockJSON: nowBlockJSON
        )
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

/// Routes by endpoint path so one double can answer the info lookup, the raw
/// transaction and the head block. The latter two are decoded from JSON, which
/// pins their wire mapping alongside the behaviour under test.
private final class TronTransactionStatusHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private let response: TronTransactionStatusResponse
    private let rawTransactionJSON: String?
    private let nowBlockJSON: String?
    private(set) var requestedPaths: [String] = []

    init(
        response: TronTransactionStatusResponse,
        rawTransactionJSON: String? = nil,
        nowBlockJSON: String? = nil
    ) {
        self.response = response
        self.rawTransactionJSON = rawTransactionJSON
        self.nowBlockJSON = nowBlockJSON
    }

    // The asynchronous signatures are protocol requirements; this in-memory
    // test double intentionally does not suspend.
    // swiftlint:disable async_without_await
    func request(_: TargetType) async throws -> HTTPResponse<Data> {
        throw HTTPError.invalidResponse
    }

    func request<T: Decodable>(
        _ target: TargetType,
        responseType _: T.Type
    ) async throws -> HTTPResponse<T> {
        requestedPaths.append(target.path)

        let decoded: T
        switch target.path {
        case "/wallet/gettransactionbyid":
            decoded = try decode(rawTransactionJSON)
        case "/wallet/getnowblock":
            decoded = try decode(nowBlockJSON)
        default:
            guard let typedResponse = response as? T else {
                throw HTTPError.invalidResponse
            }
            decoded = typedResponse
        }

        let urlResponse = HTTPURLResponse(
            url: URL(string: "https://test.local")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return HTTPResponse(data: decoded, response: urlResponse)
    }

    private func decode<T: Decodable>(_ json: String?) throws -> T {
        guard let json else { throw HTTPError.invalidResponse }
        return try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func requestEmpty(_: TargetType) async throws -> HTTPResponse<EmptyResponse> {
        throw HTTPError.invalidResponse
    }
    // swiftlint:enable async_without_await
}
