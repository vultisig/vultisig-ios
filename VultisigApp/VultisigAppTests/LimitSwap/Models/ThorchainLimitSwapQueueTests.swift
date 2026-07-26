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
        // `trade_target` is `MsgSwap.TradeTarget` verbatim — half of the pair
        // THORChain addresses a resting order by, and the cross-check that
        // guards a cancel memo built from locally-recorded values.
        XCTAssertEqual(entry.swap.tradeTarget, "15979057441")
        XCTAssertEqual(entry.swap.state?.deposit, "37556623288")
        XCTAssertEqual(entry.swap.state?.inAmount, "0")
        XCTAssertEqual(entry.swap.state?.outAmount, "0")
        XCTAssertEqual(entry.swap.state?.failedSwapReasons, [])
    }

    /// ⚠️ The assets THORChain itself holds for the order — i.e. AFTER
    /// `fuzzyAssetMatch` expanded whatever the placement memo abbreviated. This
    /// is the only place a cancel can read the full contract back from, so the
    /// keys are pinned.
    func testDecodesTheAssetsTheOrderIsIndexedUnder() throws {
        let json = """
        {"limit_swaps":[
          {"time_to_expiry_blocks":"100",
           "swap":{"tx":{"id":"ASSETS1","from_address":"thor1sender",
                         "coins":[{"asset":"THOR.RUNE","amount":"370939666"}],
                         "memo":"=<:ETH.USDC-06EB48:0x03c4:167889485/14400/0"},
                   "target_asset":"ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
                   "trade_target":"167889485",
                   "state":{"deposit":"370939666","in":"0","out":"0"}}}
        ]}
        """

        let swap = try XCTUnwrap(decode(ThorchainLimitSwapQueueResponse.self, json).limitSwaps?.first?.swap)

        XCTAssertEqual(swap.tx.coins?.first?.asset?.memoForm, "THOR.RUNE")
        XCTAssertEqual(swap.tx.coins?.first?.amount, "370939666")
        XCTAssertEqual(
            swap.targetAsset?.memoForm,
            "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
            "the placement memo said ETH.USDC-06EB48; the order is indexed under the resolved asset"
        )
    }

    /// A `common.Asset` marshalled as a protobuf message rather than through its
    /// own `MarshalJSON` arrives as an object of chain/symbol/flags. Which shape
    /// a route emits is a property of its marshaller, and this decoder feeds a
    /// string we then SIGN — so both are accepted rather than guessed at.
    func testDecodesAnAssetGivenInItsExpandedObjectForm() throws {
        let json = """
        {"limit_swaps":[
          {"swap":{"tx":{"id":"OBJ1","coins":[
                     {"asset":{"chain":"ETH","symbol":"USDC-0XA0B8","ticker":"USDC","secured":true},"amount":"1"}]},
                   "target_asset":{"chain":"BTC","symbol":"BTC","ticker":"BTC","synth":false,"trade":false,"secured":false}}}
        ]}
        """

        let swap = try XCTUnwrap(decode(ThorchainLimitSwapQueueResponse.self, json).limitSwaps?.first?.swap)

        XCTAssertEqual(swap.tx.coins?.first?.asset?.memoForm, "ETH-USDC-0XA0B8", "secured uses `-`")
        XCTAssertEqual(swap.targetAsset?.memoForm, "BTC.BTC", "no flags set means layer-1 `.`")
    }

    /// An entry with no assets at all must still decode: the cancel path treats
    /// their absence as "not observed", never as an empty asset.
    func testDecodesAnEntryWithNoAssets() throws {
        let json = #"{"limit_swaps":[{"swap":{"tx":{"id":"NOASSETS"}}}]}"#

        let swap = try XCTUnwrap(decode(ThorchainLimitSwapQueueResponse.self, json).limitSwaps?.first?.swap)

        XCTAssertNil(swap.tx.coins)
        XCTAssertNil(swap.targetAsset)
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

    // MARK: - TargetType wiring

    func testLimitSwapQueueScopesToTheSender() {
        let target = ThorchainMainnetAPI(.limitSwapQueue(sender: "thor1sender"))

        XCTAssertEqual(target.path, "/thorchain/queue/limit_swaps")
        guard case let .requestParameters(params, _) = target.task else {
            return XCTFail("expected sender to be sent as a query parameter, got \(target.task)")
        }
        XCTAssertEqual(params["sender"] as? String, "thor1sender")
    }

    /// A 400 from the queue list is a real failure and must still throw.
    func testLimitSwapQueueUsesDefaultValidation() {
        let target = ThorchainMainnetAPI(.limitSwapQueue(sender: "thor1sender"))

        guard case .successCodes = target.validationType else {
            return XCTFail("expected successCodes, got \(target.validationType)")
        }
    }

    func testTheLimitSwapQueueUsesTheLCDHost() {
        let host = URL(staticString: "https://example.invalid/lcd")
        let queue = ThorchainMainnetAPI(.limitSwapQueue(sender: nil), lcdHost: host, rpcHost: URL(staticString: "https://example.invalid/rpc"))

        XCTAssertEqual(queue.baseURL, host)
    }
}
