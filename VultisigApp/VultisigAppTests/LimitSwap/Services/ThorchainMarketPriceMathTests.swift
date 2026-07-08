//
//  ThorchainMarketPriceMathTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import BigInt
import XCTest

/// `ThorchainService.marketPrice` — the 1e8 fixed-point math behind the
/// limit-swap market-price reference, plus its three throw paths. Previously
/// only the mock was exercised; this pins the real derivation.
final class ThorchainMarketPriceMathTests: XCTestCase {

    func testOneBtcToSixteenAndAHalfEth() throws {
        // 16.5 ETH out (1e8 units) for 1 BTC (8 dp) in → 16.5 target per source.
        let price = try ThorchainService.marketPrice(
            expectedAmountOut: "1650000000",  // 16.5 × 1e8
            sourceAmount: BigInt(100_000_000), // 1 BTC
            sourceDecimals: 8
        )
        XCTAssertEqual(price, Decimal(string: "16.5")!)
    }

    func testOneEthToFractionalBtc() throws {
        // 0.0625 BTC out for 1 ETH (18 dp) in.
        let price = try ThorchainService.marketPrice(
            expectedAmountOut: "6250000",  // 0.0625 × 1e8
            sourceAmount: BigInt("1000000000000000000"), // 1 ETH
            sourceDecimals: 18
        )
        XCTAssertEqual(price, Decimal(string: "0.0625")!)
    }

    func testScalesByOneEightNotSourceDecimals() throws {
        // Half a BTC in → the price is still per-1-source-unit (target/source).
        let price = try ThorchainService.marketPrice(
            expectedAmountOut: "825000000",  // 8.25 ETH for 0.5 BTC
            sourceAmount: BigInt(50_000_000),
            sourceDecimals: 8
        )
        XCTAssertEqual(price, Decimal(string: "16.5")!) // 8.25 / 0.5
    }

    func testThrowsInvalidExpectedAmount() {
        XCTAssertThrowsError(
            try ThorchainService.marketPrice(expectedAmountOut: "not-a-number", sourceAmount: BigInt(1), sourceDecimals: 8)
        ) { error in
            guard case LimitSwapQuoteError.invalidExpectedAmount(let raw) = error else {
                return XCTFail("Expected invalidExpectedAmount, got \(error)")
            }
            XCTAssertEqual(raw, "not-a-number")
        }
    }

    func testThrowsZeroSourceAmount() {
        XCTAssertThrowsError(
            try ThorchainService.marketPrice(expectedAmountOut: "1650000000", sourceAmount: 0, sourceDecimals: 8)
        ) { error in
            XCTAssertEqual(error as? LimitSwapQuoteError, .zeroSourceAmount)
        }
    }
}
