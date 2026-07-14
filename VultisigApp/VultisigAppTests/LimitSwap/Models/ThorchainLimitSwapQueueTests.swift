//
//  ThorchainLimitSwapQueueTests.swift
//  VultisigAppTests
//
//  Decoding pinned against payloads captured live from mainnet. The wire shape
//  has two traps this locks down: the list is an OBJECT (not a bare array), and
//  every number — including the fill amounts — is a STRING.
//

import XCTest
@testable import VultisigApp

final class ThorchainLimitSwapQueueTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - queue/limit_swaps

    /// Captured from mainnet: `GET /thorchain/queue/limit_swaps?sender=…`.
    func testDecodesALiveRestingOrderEntry() throws {
        let json = """
        {"limit_swaps":[
          {"ratio":"42546576","blocks_since_created":"4131","time_to_expiry_blocks":"39069",
           "created_timestamp":"0",
           "swap":{"tx":{"id":"ABC123","from_address":"thor1sender","memo":"=<:BTC.BTC:bc1qdest:1.5e6/43200/0:va:50"},
                   "swap_type":"limit","trade_target":"15979057441",
                   "state":{"deposit":"37556623288","in":"0","out":"0","failed_swap_reasons":[]}}}
        ]}
        """

        let response = try decode(ThorchainLimitSwapQueueResponse.self, json)

        XCTAssertEqual(response.limitSwaps?.count, 1)
        let entry = try XCTUnwrap(response.limitSwaps?.first)
        XCTAssertEqual(entry.timeToExpiryBlocks, "39069")
        XCTAssertEqual(entry.blocksSinceCreated, "4131")
        XCTAssertEqual(entry.swap.tx.id, "ABC123")
        XCTAssertEqual(entry.swap.tx.fromAddress, "thor1sender")
        XCTAssertEqual(entry.swap.state?.deposit, "37556623288")
        XCTAssertEqual(entry.swap.state?.inAmount, "0")
        XCTAssertEqual(entry.swap.state?.outAmount, "0")
        XCTAssertEqual(entry.swap.state?.failedSwapReasons, [])
    }

    /// The response is an object wrapping the list. Decoding it as a bare array
    /// is the obvious mistake and would fail at runtime against mainnet.
    func testDecodingRejectsABareArrayShape() {
        XCTAssertThrowsError(try decode(ThorchainLimitSwapQueueResponse.self, "[]"))
    }

    /// An explicit empty array is a real answer: the sender has no resting
    /// orders.
    func testDecodesAnExplicitlyEmptyQueue() throws {
        let response = try decode(ThorchainLimitSwapQueueResponse.self, #"{"limit_swaps":[]}"#)

        XCTAssertEqual(response.limitSwaps, [])
    }

    /// An ABSENT key is NOT an empty queue. Disappearance from the list is what
    /// marks an order terminal, so flattening "we didn't understand this
    /// response" into "you have no resting orders" would close every tracked
    /// order at once. It must stay distinguishable.
    func testAMissingLimitSwapsKeyIsAmbiguousNotEmpty() throws {
        let response = try decode(ThorchainLimitSwapQueueResponse.self, "{}")

        XCTAssertNil(response.limitSwaps)
    }

    /// A partially-filled order: `0 < in < deposit`, with `out` paid so far.
    func testDecodesAPartiallyFilledOrder() throws {
        let json = """
        {"limit_swaps":[
          {"time_to_expiry_blocks":"100",
           "swap":{"tx":{"id":"PARTIAL1"},
                   "state":{"deposit":"1000","in":"400","out":"25","failed_swap_reasons":[]}}}
        ]}
        """

        let state = try XCTUnwrap(decode(ThorchainLimitSwapQueueResponse.self, json).limitSwaps?.first?.swap.state)

        XCTAssertEqual(state.deposit, "1000")
        XCTAssertEqual(state.inAmount, "400")
        XCTAssertEqual(state.outAmount, "25")
    }

    /// `failed_swap_reasons` on a RESTING order means "tried and missed, still
    /// resting" — not a failure. Decoding must surface it without implying one.
    func testDecodesFailedSwapReasonsOnAStillRestingOrder() throws {
        let json = """
        {"limit_swaps":[
          {"time_to_expiry_blocks":"100",
           "swap":{"tx":{"id":"TRIED1"},
                   "state":{"deposit":"1000","in":"0","out":"0",
                            "failed_swap_reasons":["swap failed: emit asset 1 less than price limit 2"]}}}
        ]}
        """

        let state = try XCTUnwrap(decode(ThorchainLimitSwapQueueResponse.self, json).limitSwaps?.first?.swap.state)

        XCTAssertEqual(state.failedSwapReasons?.count, 1)
        XCTAssertEqual(state.inAmount, "0", "still resting — nothing swapped")
    }

    /// Unknown/added fields must not break decoding: THORNode ships new keys
    /// without warning, and a hard failure would strand every tracked order.
    func testDecodingToleratesUnknownFields() throws {
        let json = """
        {"limit_swaps":[
          {"time_to_expiry_blocks":"100","some_new_field":"whatever",
           "swap":{"tx":{"id":"NEW1","brand_new":"x"},"state":{"deposit":"1","in":"0","out":"0"}}}
        ]}
        """

        XCTAssertEqual(try decode(ThorchainLimitSwapQueueResponse.self, json).limitSwaps?.first?.swap.tx.id, "NEW1")
    }

    func testDecodesAnEntryWithNoStateBlock() throws {
        let json = #"{"limit_swaps":[{"swap":{"tx":{"id":"NOSTATE"}}}]}"#

        let entry = try XCTUnwrap(decode(ThorchainLimitSwapQueueResponse.self, json).limitSwaps?.first)

        XCTAssertEqual(entry.swap.tx.id, "NOSTATE")
        XCTAssertNil(entry.swap.state)
    }

    // MARK: - queue/swap/details 400 body

    /// Captured from mainnet: the 400 body returned once an order has closed.
    func testDecodesTheClosedOrderErrorBody() throws {
        let json = """
        {"code":3,"message":"swap with tx_id ABC123 not found in any queue: invalid request"}
        """

        let error = try decode(ThorchainQueueErrorResponse.self, json)

        XCTAssertEqual(error.code, 3)
        XCTAssertTrue(error.indicatesOrderClosed(forTxHash: "ABC123"))
    }

    /// Tx-id hex case carries no meaning, so it must not decide whether an
    /// order is closed.
    func testTheClosedCheckIsCaseInsensitiveOnTheHash() throws {
        let json = """
        {"code":3,"message":"swap with tx_id ABC123 not found in any queue: invalid request"}
        """

        XCTAssertTrue(try decode(ThorchainQueueErrorResponse.self, json).indicatesOrderClosed(forTxHash: "abc123"))
    }

    /// A response about a DIFFERENT order must never close this one.
    func testAnErrorNamingAnotherHashDoesNotCloseThisOrder() throws {
        let json = """
        {"code":3,"message":"swap with tx_id OTHER999 not found in any queue: invalid request"}
        """

        XCTAssertFalse(try decode(ThorchainQueueErrorResponse.self, json).indicatesOrderClosed(forTxHash: "ABC123"))
    }

    /// The hash is compared as a COMPLETE token, not searched for: a truncated
    /// or short hash must not match a longer one and close the wrong order.
    func testAPartialHashDoesNotCloseALongerOrder() throws {
        let json = """
        {"code":3,"message":"swap with tx_id ABC123 not found in any queue: invalid request"}
        """

        XCTAssertFalse(try decode(ThorchainQueueErrorResponse.self, json).indicatesOrderClosed(forTxHash: "ABC"))
    }

    /// Nor may a longer requested hash match a shorter named one.
    func testALongerHashDoesNotMatchAShorterNamedOne() throws {
        let json = """
        {"code":3,"message":"swap with tx_id ABC not found in any queue: invalid request"}
        """

        XCTAssertFalse(try decode(ThorchainQueueErrorResponse.self, json).indicatesOrderClosed(forTxHash: "ABC123"))
    }

    /// A word from the message itself is not a hash match.
    func testAWordFromTheMessageIsNotAHashMatch() throws {
        let json = """
        {"code":3,"message":"swap with tx_id ABC123 not found in any queue: invalid request"}
        """

        XCTAssertFalse(try decode(ThorchainQueueErrorResponse.self, json).indicatesOrderClosed(forTxHash: "queue"))
    }

    /// A genuine bad request must NOT be read as "order closed" — that would
    /// silently mark a still-resting order terminal.
    func testAGenuineBadRequestIsNotReadAsClosed() throws {
        let error = try decode(ThorchainQueueErrorResponse.self, #"{"code":3,"message":"invalid request"}"#)

        XCTAssertFalse(error.indicatesOrderClosed(forTxHash: "ABC123"))
    }

    /// Right message, wrong code — the contract we verified is code 3. Anything
    /// else is a response we don't understand, so it stays resting.
    func testAnUnexpectedCodeIsNotReadAsClosed() throws {
        let json = """
        {"code":5,"message":"swap with tx_id ABC123 not found in any queue: invalid request"}
        """

        XCTAssertFalse(try decode(ThorchainQueueErrorResponse.self, json).indicatesOrderClosed(forTxHash: "ABC123"))
    }

    func testAMissingCodeIsNotReadAsClosed() throws {
        let json = """
        {"message":"swap with tx_id ABC123 not found in any queue: invalid request"}
        """

        XCTAssertFalse(try decode(ThorchainQueueErrorResponse.self, json).indicatesOrderClosed(forTxHash: "ABC123"))
    }

    /// A reworded message is a contract we no longer recognise. Unknown must
    /// stay unknown — retried, not closed.
    func testARewordedMessageIsNotReadAsClosed() throws {
        let json = """
        {"code":3,"message":"swap with tx_id ABC123 is NOT PRESENT IN ANY QUEUE: invalid request"}
        """

        XCTAssertFalse(try decode(ThorchainQueueErrorResponse.self, json).indicatesOrderClosed(forTxHash: "ABC123"))
    }

    func testAnEmptyErrorBodyIsNotReadAsClosed() throws {
        let error = try decode(ThorchainQueueErrorResponse.self, "{}")

        XCTAssertFalse(error.indicatesOrderClosed(forTxHash: "ABC123"))
    }

    /// Guard against a caller passing an empty hash: with a substring match, an
    /// empty needle matches everything and would close the order.
    func testAnEmptyRequestedHashNeverCloses() throws {
        let json = """
        {"code":3,"message":"swap with tx_id ABC123 not found in any queue: invalid request"}
        """

        XCTAssertFalse(try decode(ThorchainQueueErrorResponse.self, json).indicatesOrderClosed(forTxHash: ""))
    }

    // MARK: - TargetType wiring

    func testLimitSwapQueueScopesToTheSender() {
        let target = ThorchainMainnetAPI(.limitSwapQueue(sender: "thor1sender"))

        XCTAssertEqual(target.path, "/thorchain/queue/limit_swaps")
        guard case let .requestParameters(params, _) = target.task else {
            return XCTFail("expected sender to be sent as a query parameter, got \(target.task)")
        }
        XCTAssertEqual(params["sender"] as? String, "thor1sender")
    }

    func testLimitSwapDetailsPinsTheHashInThePath() {
        let target = ThorchainMainnetAPI(.limitSwapDetails(txHash: "ABC123"))

        XCTAssertEqual(target.path, "/thorchain/queue/swap/details/ABC123")
    }

    /// The 400-as-state seam: without this the HTTP client throws on a closed
    /// order and the tracker can't tell "closed" from "network down".
    func testLimitSwapDetailsAccepts400AsAState() {
        let target = ThorchainMainnetAPI(.limitSwapDetails(txHash: "ABC123"))

        guard case let .customCodes(codes) = target.validationType else {
            return XCTFail("expected customCodes, got \(target.validationType)")
        }
        XCTAssertEqual(codes.sorted(), [200, 400])
    }

    /// The queue list has no 400-as-state contract — a 400 there is a real
    /// failure and must still throw.
    func testLimitSwapQueueUsesDefaultValidation() {
        let target = ThorchainMainnetAPI(.limitSwapQueue(sender: "thor1sender"))

        guard case .successCodes = target.validationType else {
            return XCTFail("expected successCodes, got \(target.validationType)")
        }
    }

    func testLimitSwapEndpointsUseTheLCDHost() {
        let host = URL(staticString: "https://example.invalid/lcd")
        let queue = ThorchainMainnetAPI(.limitSwapQueue(sender: nil), lcdHost: host, rpcHost: URL(staticString: "https://example.invalid/rpc"))
        let details = ThorchainMainnetAPI(.limitSwapDetails(txHash: "ABC"), lcdHost: host, rpcHost: URL(staticString: "https://example.invalid/rpc"))

        XCTAssertEqual(queue.baseURL, host)
        XCTAssertEqual(details.baseURL, host)
    }
}
