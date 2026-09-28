//
//  BondRewardMathTests.swift
//  VultisigAppTests
//
//  Pins the bond-provider share formula (also used live by
//  `calculateBondMetrics`) against a verified mainnet snapshot so both the
//  card's Last Reward and the rewards sheet's history rows compute the same
//  number the same way.
//

import XCTest
@testable import VultisigApp

final class BondRewardMathTests: XCTestCase {

    /// Verbatim from `thorchain_api/thorchain/node/thor10czf2s89h79fsjmqqck85cdqeq536hw5ngz4lt?height=27914369`
    /// (confirmed live 2026-09-27): `current_award=103341961766`,
    /// `node_operator_fee=2000`bps, `total_bond=112307744558083`, top
    /// provider bond `29511174914053` (~26.28%). The remainder is folded
    /// into one synthetic "everyone else" provider so the fixture is compact
    /// while `myBond`/`totalBond` stay exactly the mainnet values.
    private static let currentAward: Decimal = 103341961766
    private static let nodeOperatorFeeBps: Decimal = 2000
    private static let topProviderBond: Decimal = 29511174914053
    private static let totalBond: Decimal = 112307744558083
    private static let topProviderAddress = "thor18zg6y8ylus8n3tpzu5xxge3yyquj03vylstrl3"

    private static let mainnetProviders: [(bondAddress: String, bond: Decimal)] = [
        (topProviderAddress, topProviderBond),
        ("thor1everyoneelse", totalBond - topProviderBond)
    ]

    func testMainnetFixtureMatchesTheIssuesStated21724Rune() {
        let share = BondRewardMath.share(
            providers: Self.mainnetProviders,
            nodeOperatorFeeBps: Self.nodeOperatorFeeBps,
            currentAward: Self.currentAward,
            myBondAddress: Self.topProviderAddress
        )

        let rune = (share?.myAward ?? 0) / pow(10, 8)
        // The issue states "~26.3% ... earned 217.24 RUNE" — assert to the
        // same 2-decimal precision it was reported at.
        XCTAssertEqual(rune.formatted(.number.precision(.fractionLength(2))), "217.24")
        XCTAssertEqual(share?.myBond, Self.topProviderBond)
    }

    func testAddressNotAmongProvidersReturnsNil() {
        let share = BondRewardMath.share(
            providers: Self.mainnetProviders,
            nodeOperatorFeeBps: Self.nodeOperatorFeeBps,
            currentAward: Self.currentAward,
            myBondAddress: "thor1neverbonded"
        )
        XCTAssertNil(share, "an address absent from bond_providers was never a provider at this snapshot")
    }

    func testZeroTotalBondDoesNotDivideByZero() {
        let providers: [(bondAddress: String, bond: Decimal)] = [("thor1x", 0)]
        let share = BondRewardMath.share(
            providers: providers,
            nodeOperatorFeeBps: 0,
            currentAward: 1000,
            myBondAddress: "thor1x"
        )
        XCTAssertEqual(share?.myAward, 0)
    }

    func testFullNodeOperatorFeeLeavesNothingForProviders() {
        let providers: [(bondAddress: String, bond: Decimal)] = [("thor1x", 100)]
        let share = BondRewardMath.share(
            providers: providers,
            nodeOperatorFeeBps: 10000,
            currentAward: 1000,
            myBondAddress: "thor1x"
        )
        XCTAssertEqual(share?.myAward, 0)
    }
}
