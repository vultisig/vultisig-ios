//
//  THORChainTransactionStatusMappingTests.swift
//  VultisigAppTests
//
//  What the done screen tells the user about a THORChain transaction.
//
//  ⚠️ The outcome is `action.type`. Midgard's `status` describes the OUTBOUND
//  and takes only `success` or `pending`, so a message THORChain REJECTED is
//  indexed as `{"type": "failed", "status": "success"}` — and reading `status`
//  put "Transaction Successful" in front of a user whose transaction the chain
//  had refused.
//
//  This provider serves every THORChain transaction — sends, bonds, deposits,
//  swaps, limit orders — so the tests below pin the shapes it must keep getting
//  right as much as the one it got wrong. The fixtures are captured from
//  mainnet Midgard.
//

import XCTest
@testable import VultisigApp

final class THORChainTransactionStatusMappingTests: XCTestCase {

    private func status(for json: String) async throws -> TransactionStatusResult {
        try await THORChainTransactionStatusProvider(httpClient: StubMidgardHTTPClient(json))
            .checkStatus(query: TransactionStatusQuery(txHash: "ABC123", chain: .thorChain))
    }

    // MARK: - A refusal is not a confirmation

    /// ⚠️ The regression, verbatim from Gaston's own history: a limit-order
    /// cancel THORChain rejected, carrying `"status": "success"`. This screen
    /// reported it CONFIRMED — a cancel the chain refused, shown as done, which
    /// is the exact false success the cancel flow exists to prevent.
    func testARejectedTransactionIsReportedFailedDespiteItsSuccessStatus() async throws {
        let result = try await status(for: Self.rejectedCancel())

        guard case let .failed(reason) = result.status else {
            return XCTFail("A rejected transaction must not read as \(result.status)")
        }
        XCTAssertTrue(
            reason.contains("could not find matching limit swap: internal error"),
            "The chain's own words are the only explanation the user gets: \(reason)"
        )
        XCTAssertTrue(reason.contains("Code: 99"), reason)
        XCTAssertEqual(result.blockNumber, 27113740)
    }

    /// The memo is this app's own outgoing memo echoed back. It explains
    /// nothing, and the reason is rendered verbatim on the done screen.
    func testTheEchoedMemoIsNotShownToTheUser() async throws {
        let result = try await status(for: Self.rejectedCancel())

        guard case let .failed(reason) = result.status else {
            return XCTFail("Expected a failure, got \(result.status)")
        }
        XCTAssertFalse(reason.contains("m=<:370939666THOR.RUNE"), reason)
    }

    /// ⚠️ `type` is checked BEFORE `status`. A `failed` action whose outbound is
    /// pending is one whose REFUND has not been sent — the verdict is already
    /// in, so waiting on the refund leg would leave a rejected transaction
    /// spinning until the poller timed out.
    func testAFailedActionIsFailedEvenWhileItsRefundIsStillPending() async throws {
        let result = try await status(for: Self.rejectedCancel(status: "pending"))

        guard case .failed = result.status else {
            return XCTFail("A rejected transaction must not read as \(result.status)")
        }
    }

    /// ⚠️ A safety property rather than an observed payload. The query is
    /// `?txid=`, so every action on the page describes the SAME transaction, and
    /// one of them saying the chain refused it settles the question wherever it
    /// sits in Midgard's newest-first ordering. Only the newest action used to
    /// be read at all.
    func testAFailedActionAnywhereOnThePageOutranksTheNewestOne() async throws {
        let result = try await status(for: Self.pageWhoseFailureIsNotNewest)

        guard case let .failed(reason) = result.status else {
            return XCTFail("A rejected transaction must not read as \(result.status)")
        }
        XCTAssertTrue(reason.contains("could not find matching limit swap"), reason)
        XCTAssertEqual(result.blockNumber, 27113740, "the height reported is the failing action's own")
    }

    func testAFailedActionWithNoMetadataStillReportsAFailure() async throws {
        let result = try await status(for: Self.failedActionWithoutMetadata)

        guard case let .failed(reason) = result.status else {
            return XCTFail("Expected a failure, got \(result.status)")
        }
        XCTAssertFalse(reason.isEmpty)
    }

    // MARK: - Everything this provider was already getting right

    func testACompletedSwapIsConfirmed() async throws {
        let result = try await status(for: Self.completedSwap())

        XCTAssertEqual(result.status, .confirmed)
        XCTAssertEqual(result.blockNumber, 27113735)
    }

    /// An outbound Midgard has not seen sent yet: still in flight, keep polling.
    func testASwapWhoseOutboundHasNotSettledIsPending() async throws {
        let result = try await status(for: Self.completedSwap(status: "pending"))

        XCTAssertEqual(result.status, .pending)
    }

    /// A resting limit order. The placement succeeded — which is all this screen
    /// claims — and the order's own fate is tracked elsewhere.
    func testALimitOrderPlacementIsConfirmed() async throws {
        let result = try await status(for: Self.limitOrderPlacement)

        XCTAssertEqual(result.status, .confirmed)
    }

    /// ⚠️ Deliberately NOT a failure. This provider serves every THORChain
    /// transaction, and a refund is a legitimate outcome in flows this change
    /// never looked at — a swap returned over its slip limit, a limit order
    /// closing unfilled. `MidgardLimitOutcomeResolver` reads refunds itself and
    /// labels them where the context to do so exists.
    func testARefundIsNotReclassifiedAsAFailure() async throws {
        let result = try await status(for: Self.refundedSwap)

        XCTAssertEqual(result.status, .confirmed)
    }

    /// Not indexed yet — the usual case in the seconds after a broadcast.
    func testNoActionsIsNotFound() async throws {
        let result = try await status(for: #"{"actions":[],"count":"0"}"#)

        XCTAssertEqual(result.status, .notFound)
    }

    // MARK: - Fixtures

    /// Verbatim from mainnet Midgard: the cancel THORChain rejected because the
    /// order it named had already left the queue.
    private static func rejectedCancel(status: String = "success") -> String {
        """
        {"actions":[{"pools":[],"type":"failed","status":"\(status)",
          "in":[{"txID":"ABC123","address":"thor1from","coins":[{"amount":"370939666","asset":"THOR.RUNE"}]}],
          "out":[],"date":"1784733471384558083","height":"27113740",
          "metadata":{"failed":{
            "code":"99",
            "memo":"m=<:370939666THOR.RUNE:167889485ETH.USDC-06EB48:0",
            "reason":"failed to execute message; message index: 0: could not find matching limit swap: internal error"
          }}}],"count":"1"}
        """
    }

    /// Two actions under one `txid`, the failure NOT first.
    private static let pageWhoseFailureIsNotNewest = """
    {"actions":[
      {"pools":[],"type":"limit_swap","status":"success",
       "in":[{"txID":"ABC123","address":"thor1from","coins":[{"amount":"370939666","asset":"THOR.RUNE"}]}],
       "out":[],"date":"1784733480000000000","height":"27113745"},
      {"pools":[],"type":"failed","status":"success",
       "in":[{"txID":"ABC123","address":"thor1from","coins":[{"amount":"370939666","asset":"THOR.RUNE"}]}],
       "out":[],"date":"1784733471384558083","height":"27113740",
       "metadata":{"failed":{"code":"99",
         "reason":"failed to execute message; message index: 0: could not find matching limit swap: internal error"}}}
    ],"count":"2"}
    """

    /// A `failed` action Midgard indexed without a metadata block. The user is
    /// still owed a failure, even without the chain's reason for it.
    private static let failedActionWithoutMetadata = """
    {"actions":[{"pools":[],"type":"failed","status":"success",
      "in":[{"txID":"ABC123","address":"thor1from","coins":[{"amount":"370939666","asset":"THOR.RUNE"}]}],
      "out":[],"date":"1784733471384558083","height":"27113740"}],"count":"1"}
    """

    private static func completedSwap(status: String = "success") -> String {
        """
        {"actions":[{"pools":["ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48"],
          "type":"swap","status":"\(status)",
          "in":[{"txID":"ABC123","address":"thor1from","coins":[{"amount":"370939666","asset":"THOR.RUNE"}]}],
          "out":[{"txID":"DEF456","address":"0xdest",
                  "coins":[{"amount":"167889485","asset":"ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48"}]}],
          "date":"1784733440727466355","height":"27113735",
          "metadata":{"swap":{"affiliateAddress":"","affiliateFee":"0","isStreamingSwap":false,
            "liquidityFee":"124912","memo":"=:ETH.USDC-06EB48:0xdest:167889485",
            "networkFees":[{"amount":"2000000","asset":"THOR.RUNE"}],
            "swapSlip":"3","swapTarget":"167889485","txType":"swap"}}}],"count":"1"}
        """
    }

    /// A resting order: the placement, and nothing else.
    private static let limitOrderPlacement = """
    {"actions":[{"pools":[],"type":"limit_swap","status":"success",
      "in":[{"txID":"ABC123","address":"thor1from","coins":[{"amount":"370939666","asset":"THOR.RUNE"}]}],
      "out":[],"date":"1784733440727466355","height":"27113735"}],"count":"1"}
    """

    /// A swap returned because it could not be filled inside its price limit.
    private static let refundedSwap = """
    {"actions":[{"pools":["ETH.ETH"],"type":"refund","status":"success",
      "in":[{"txID":"ABC123","address":"thor1from","coins":[{"amount":"300000000","asset":"THOR.RUNE"}]}],
      "out":[{"txID":"DEF456","address":"thor1from","coins":[{"amount":"298000000","asset":"THOR.RUNE"}]}],
      "date":"1784733471384558083","height":"27113740",
      "metadata":{"refund":{"code":"99",
        "reason":"emit asset 145824 less than price limit 149000",
        "networkFees":[{"amount":"2000000","asset":"THOR.RUNE"}]}}}],"count":"1"}
    """
}

// MARK: - Fakes

private struct StubMidgardHTTPClient: HTTPClientProtocol {
    private let json: String

    init(_ json: String) {
        self.json = json
    }

    func request(_: TargetType) async throws -> HTTPResponse<Data> { // swiftlint:disable:this async_without_await
        let url = URL(string: "https://example.invalid")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: Data(json.utf8), response: response)
    }

    func requestEmpty(_: TargetType) async throws -> HTTPResponse<EmptyResponse> { // swiftlint:disable:this async_without_await
        throw HTTPError.statusCode(500, Data())
    }
}
