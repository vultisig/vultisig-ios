//
//  SolanaStakingAPYResolverTests.swift
//  VultisigAppTests
//
//  Pins the two-source APY resolution: the Stakewiz `apy_estimate` passthrough
//  wins when present; otherwise the on-chain inflation/fraction-staked fallback
//  applies; otherwise nil (the view hides the row).
//

@testable import VultisigApp
import Foundation
import XCTest

final class SolanaStakingAPYResolverTests: XCTestCase {

    private let resolver = SolanaStakingAPYResolver()

    private func validator(commission: Int, activatedStake: UInt64 = 1_000) -> SolanaValidator {
        SolanaValidator(
            votePubkey: "Vote1",
            nodePubkey: "Node1",
            activatedStake: activatedStake,
            commission: commission,
            epochVoteAccount: true,
            isDelinquent: false
        )
    }

    func testMetadataPassthroughWins() {
        let apy = resolver.apy(
            for: validator(commission: 5),
            metadataAPY: Decimal(string: "0.0712"),
            inflationRate: 0.05,
            totalActivatedStake: 1_000,
            totalSupplyLamports: 10_000
        )
        XCTAssertEqual((apy as NSDecimalNumber?)?.doubleValue ?? 0, 0.0712, accuracy: 0.00001)
    }

    func testFallsBackToOnChainWhenNoMetadata() {
        // inflation 0.08, fractionStaked = 5000/10000 = 0.5, commission 10%.
        // APR = (0.08 / 0.5) * 0.9 = 0.144 → APY = (1 + 0.144/182)^182 - 1.
        let apy = resolver.apy(
            for: validator(commission: 10, activatedStake: 5_000),
            metadataAPY: nil,
            inflationRate: 0.08,
            totalActivatedStake: 5_000,
            totalSupplyLamports: 10_000
        )
        XCTAssertNotNil(apy)
        let aprDouble = 0.144
        let epochs = 182.0
        let expected = pow(1 + aprDouble / epochs, epochs) - 1
        XCTAssertEqual((apy as NSDecimalNumber?)?.doubleValue ?? 0, expected, accuracy: 0.0005)
    }

    func testReturnsNilWhenNoSourceAvailable() {
        let apy = resolver.apy(
            for: validator(commission: 5),
            metadataAPY: nil,
            inflationRate: nil,
            totalActivatedStake: 0,
            totalSupplyLamports: nil
        )
        XCTAssertNil(apy)
    }

    func testZeroMetadataDoesNotShortCircuitFallback() {
        // A zero/empty Stakewiz estimate must not block the on-chain fallback.
        let apy = resolver.apy(
            for: validator(commission: 0, activatedStake: 5_000),
            metadataAPY: Decimal(0),
            inflationRate: 0.06,
            totalActivatedStake: 5_000,
            totalSupplyLamports: 10_000
        )
        // Pin the on-chain fallback value so a regression that returns the zero
        // metadataAPY (instead of taking the fallback) is caught: apr =
        // (0.06 / 0.5) * 1, compounded over 182 epochs.
        let expected = pow(1 + ((0.06 / 0.5) / 182.0), 182.0) - 1
        XCTAssertEqual((apy as NSDecimalNumber?)?.doubleValue ?? 0, expected, accuracy: 0.0005)
    }

    func testOnChainNilWhenSupplyMissing() {
        let apy = SolanaStakingAPYResolver.onChainAPY(
            inflationRate: 0.07,
            commission: 5,
            totalActivatedStake: 5_000,
            totalSupplyLamports: nil
        )
        XCTAssertNil(apy)
    }

    func testOnChainNilWhenFullCommission() {
        // 100% commission nets the delegator to 0 APR → nil.
        let apy = SolanaStakingAPYResolver.onChainAPY(
            inflationRate: 0.07,
            commission: 100,
            totalActivatedStake: 5_000,
            totalSupplyLamports: 10_000
        )
        XCTAssertNil(apy)
    }
}
