//
//  BitcoinByteFeeTests.swift
//  VultisigAppTests
//
//  Pins the Bitcoin sat/vB rule: the projected next block's median fee, never
//  below Blockchair's suggestion, plus a 25% margin, rounded up, floored at
//  2 sat/vB. Without a usable projection the rate is Blockchair x2.5.
//

@testable import VultisigApp
import XCTest
import BigInt

final class BitcoinByteFeeTests: XCTestCase {

    private func rate(blockchair: Int, median: Double?) -> BigInt {
        BlockChainService.bitcoinByteFee(
            blockchairSatsPerByte: BigInt(blockchair),
            nextBlockMedianFee: median
        )
    }

    func testProjectedMedianWithMarginRoundsUp() {
        XCTAssertEqual(rate(blockchair: 2, median: 2.4), BigInt(3))
        XCTAssertEqual(rate(blockchair: 2, median: 4.17), BigInt(6))
        XCTAssertEqual(rate(blockchair: 2, median: 3.9), BigInt(5))
        XCTAssertEqual(rate(blockchair: 1, median: 1.6004), BigInt(3))
    }

    func testBlockchairIsTheLowerBound() {
        XCTAssertEqual(rate(blockchair: 2, median: 0.13), BigInt(3))
        XCTAssertEqual(rate(blockchair: 1, median: 0.5), BigInt(2))
        XCTAssertEqual(rate(blockchair: 40, median: 10), BigInt(50))
    }

    /// Blockchair 0 and median 0.4 compute to 1 sat/vB; only the floor lifts it.
    func testTwoSatFloorAppliesWhenTheRuleComputesLess() {
        XCTAssertEqual(rate(blockchair: 0, median: 0.4), BigInt(2))
    }

    func testUnusableProjectionFallsBackToBlockchairTimesTwoAndAHalf() {
        let unusable: [Double?] = [nil, 0, .nan, .infinity, 6_000, -1]
        for median in unusable {
            XCTAssertEqual(rate(blockchair: 2, median: median), BigInt(5), "median \(String(describing: median))")
        }
    }
}
