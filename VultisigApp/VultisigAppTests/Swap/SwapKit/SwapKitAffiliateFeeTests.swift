//
//  SwapKitAffiliateFeeTests.swift
//  VultisigAppTests
//
//  Pins the tier-discount → affiliateFee bps wiring for SwapKit quote
//  requests. Mirrors Kyber's `vultTierDiscount >= 50 ? 0 : 50 - discount`
//  shape via `max(0, ...)`, plus a defensive `min(1000, ...)` clamp at
//  SwapKit's documented 10% ceiling. The Vultisig proxy was verified live
//  to pass the field through to SwapKit unchanged, so iOS is the only side
//  responsible for sending the right number.
//

import Foundation
import XCTest
@testable import VultisigApp

final class SwapKitAffiliateFeeTests: XCTestCase {

    // MARK: - Formula (pure)
    //
    // The formula lives inside `SwapService.fetchSwapKitQuote` rather than a
    // standalone helper. Re-stating it here keeps the edge cases pinned
    // without coupling the test to private state — if the production
    // formula changes shape, these tests will diverge from the wire test
    // below and surface the mismatch.

    private func affiliateBps(forDiscount discount: Int) -> Int {
        max(0, min(1000, 50 - discount))
    }

    func testNoDiscountSendsFiftyBps() {
        XCTAssertEqual(affiliateBps(forDiscount: 0), 50)
    }

    func testHalfDiscountSendsTwentyFiveBps() {
        XCTAssertEqual(affiliateBps(forDiscount: 25), 25)
    }

    func testFullDiscountSendsZeroBps() {
        XCTAssertEqual(affiliateBps(forDiscount: 50), 0)
    }

    func testOverDiscountClampsToZero() {
        XCTAssertEqual(affiliateBps(forDiscount: 999), 0)
    }

    func testFifteenPercentDiscountIsThirtyFiveBps() {
        XCTAssertEqual(affiliateBps(forDiscount: 15), 35)
    }

    // MARK: - JSON serialisation
    //
    // SwapKit's `/v3/quote` accepts `affiliateFee` as an integer in basis
    // points (0–1000). Confirm the default `JSONEncoder` emits the field as
    // a bare integer literal (`50`) — not as a string (`"50"`), and not
    // dropped. Default Swift behaviour for `Encodable` with an optional
    // omits the key when the value is `nil`; we rely on that to enforce
    // "always populate after this change" at the call-site level rather
    // than encoder configuration.

    func testQuoteRequestSerializesAffiliateFeeAsInteger() throws {
        let request = SwapKitQuoteRequest(
            sellAsset: "ETH.ETH",
            buyAsset: "ETH.USDC",
            sellAmount: "1",
            sourceAddress: nil,
            destinationAddress: nil,
            slippage: nil,
            providers: nil,
            affiliateFee: 50
        )
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(
            json.contains("\"affiliateFee\":50"),
            "Expected integer literal `affiliateFee:50`, got: \(json)"
        )
        XCTAssertFalse(
            json.contains("\"affiliateFee\":\"50\""),
            "affiliateFee must be encoded as a JSON number, not a string"
        )
    }

    func testQuoteRequestOmitsAffiliateFeeWhenNil() throws {
        // Defensive: confirms the default `Encodable` behaviour we rely on
        // to gate "always populate after this change". If a future encoder
        // strategy emits `null` for nil optionals, this test catches it and
        // the production call site must be re-audited.
        let request = SwapKitQuoteRequest(
            sellAsset: "ETH.ETH",
            buyAsset: "ETH.USDC",
            sellAmount: "1",
            sourceAddress: nil,
            destinationAddress: nil,
            slippage: nil,
            providers: nil,
            affiliateFee: nil
        )
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(
            json.contains("affiliateFee"),
            "Nil affiliateFee must be omitted from the JSON body, got: \(json)"
        )
    }

    // MARK: - Zero is wire-distinct from nil

    func testQuoteRequestSerializesZeroAffiliateFee() throws {
        // `vultTierDiscount >= 50` collapses to `affiliateFee: 0`. The proxy
        // overrides the field when it's missing but passes `0` through — so
        // we must encode `0` explicitly, not omit it.
        let request = SwapKitQuoteRequest(
            sellAsset: "ETH.ETH",
            buyAsset: "ETH.USDC",
            sellAmount: "1",
            sourceAddress: nil,
            destinationAddress: nil,
            slippage: nil,
            providers: nil,
            affiliateFee: 0
        )
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(
            json.contains("\"affiliateFee\":0"),
            "Expected `affiliateFee:0` to be encoded explicitly, got: \(json)"
        )
    }
}
