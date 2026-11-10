//
//  EthereumPriorityFeeTests.swift
//  VultisigAppTests
//
//  Pins the Ethereum mainnet tip rule: from recent blocks' 75th-percentile
//  rewards, Low takes the smallest, Normal the median, Fast the largest, each
//  raised to 0.2 gwei for sends and 0.5 gwei for swaps.
//

@testable import VultisigApp
import XCTest
import BigInt

final class EthereumPriorityFeeTests: XCTestCase {

    private func tip(_ rewards: [Int], mode: FeeMode = .normal, swap: Bool = false) -> BigInt? {
        EthereumFeeService.ethereumPriorityFee(
            rewards: rewards.map { BigInt($0) },
            mode: mode,
            usesSwapFloor: swap
        )
    }

    func testSendFloorLiftsAQuietMarket() {
        XCTAssertEqual(tip([10_000_000, 15_000_000, 20_000_000]), BigInt(200_000_000))
        XCTAssertEqual(EthereumFeeService.ethereumSendPriorityFeeFloor, BigInt(200_000_000))
    }

    func testMedianAboveTheFloorIsKept() {
        XCTAssertEqual(tip([250_000_000, 310_000_000, 900_000_000]), BigInt(310_000_000))
    }

    func testSwapUsesTheHalfGweiFloor() {
        XCTAssertEqual(tip([50_000_000, 100_000_000, 150_000_000], swap: true), BigInt(500_000_000))
    }

    func testUnsortedRewardsAreRankedBeforeTiering() {
        let rewards = [900_000_000, 250_000_000, 400_000_000]
        XCTAssertEqual(tip(rewards, mode: .safeLow), BigInt(250_000_000))
        XCTAssertEqual(tip(rewards, mode: .normal), BigInt(400_000_000))
        XCTAssertEqual(tip(rewards, mode: .fast), BigInt(900_000_000))
    }

    func testEvenLengthMedianAveragesTheMiddlePair() {
        XCTAssertEqual(tip([300_000_000, 900_000_000, 250_000_000, 400_000_000]), BigInt(350_000_000))
    }

    func testSendTiersAreDistinctAboveTheFloor() {
        let fees = EthereumFeeService.ethereumSendPriorityFees(
            rewards: [250_000_000, 400_000_000, 900_000_000].map { BigInt($0) }
        )
        XCTAssertEqual(fees, [.safeLow: BigInt(250_000_000), .normal: BigInt(400_000_000), .fast: BigInt(900_000_000)])
    }

    func testNoRewardsMeansNoMarketTip() {
        XCTAssertNil(tip([]))
        XCTAssertNil(EthereumFeeService.ethereumSendPriorityFees(rewards: []))
    }
}
