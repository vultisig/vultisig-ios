//
//  TonPoolSelectionTests.swift
//  VultisigAppTests
//
//  Pins the TON pool picker's sort/filter contract and the decode of the
//  tonapi.io `/v2/staking/pools` list response.
//

@testable import VultisigApp
import XCTest

@MainActor
final class TonPoolSelectionTests: XCTestCase {

    private func entry(
        address: String,
        apy: Double,
        verified: Bool,
        current: Int? = 100,
        max: Int? = 30000,
        minStake: Int64 = 50_000_000_000
    ) -> TonStakingPoolListEntry {
        TonStakingPoolListEntry(
            address: address,
            name: "Pool \(address)",
            apy: apy,
            minStake: minStake,
            verified: verified,
            currentNominators: current,
            maxNominators: max,
            implementation: "whales"
        )
    }

    // MARK: - sortAndFilter

    func testSortAndFilterKeepsOnlyVerified() {
        let raw = [
            entry(address: "a", apy: 10, verified: true),
            entry(address: "b", apy: 20, verified: false)
        ]
        let result = TonPoolSelectionViewModel.sortAndFilter(raw, decimals: 9)
        XCTAssertEqual(result.map(\.address), ["a"])
    }

    func testSortAndFilterSortsByApyDescending() {
        let raw = [
            entry(address: "low", apy: 5, verified: true),
            entry(address: "high", apy: 15, verified: true),
            entry(address: "mid", apy: 10, verified: true)
        ]
        let result = TonPoolSelectionViewModel.sortAndFilter(raw, decimals: 9)
        XCTAssertEqual(result.map(\.address), ["high", "mid", "low"])
    }

    func testSortAndFilterDropsFullPools() {
        let raw = [
            entry(address: "open", apy: 10, verified: true, current: 100, max: 30000),
            entry(address: "full", apy: 20, verified: true, current: 30000, max: 30000)
        ]
        let result = TonPoolSelectionViewModel.sortAndFilter(raw, decimals: 9)
        XCTAssertEqual(result.map(\.address), ["open"])
    }

    func testSortAndFilterScalesMinStakeFromNanotons() {
        let raw = [entry(address: "a", apy: 10, verified: true, minStake: 50_000_000_000)]
        let result = TonPoolSelectionViewModel.sortAndFilter(raw, decimals: 9)
        XCTAssertEqual(result.first?.minStake, 50)
    }

    // MARK: - Decode

    func testDecodeStakingPoolsResponse() throws {
        let json = """
        {
          "pools": [
            {
              "address": "0:a44757069a7b04e393782b4a2d3e5e449f19d16a4986a9e25436e6b97e45a16a",
              "name": "Whales Nominators Queue #1",
              "total_amount": 969152181255370,
              "implementation": "whales",
              "apy": 13.2693375,
              "min_stake": 50000000000,
              "cycle_start": 1782402824,
              "cycle_end": 1782501428,
              "verified": true,
              "current_nominators": 1807,
              "max_nominators": 30000
            }
          ],
          "implementations": {}
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(TonStakingPoolsResponse.self, from: data)
        XCTAssertEqual(response.pools.count, 1)
        let pool = try XCTUnwrap(response.pools.first)
        XCTAssertEqual(pool.address, "0:a44757069a7b04e393782b4a2d3e5e449f19d16a4986a9e25436e6b97e45a16a")
        XCTAssertEqual(pool.name, "Whales Nominators Queue #1")
        XCTAssertEqual(pool.apy, 13.2693375, accuracy: 0.0001)
        XCTAssertEqual(pool.minStake, 50_000_000_000)
        XCTAssertTrue(pool.verified)
        XCTAssertEqual(pool.currentNominators, 1807)
        XCTAssertEqual(pool.maxNominators, 30000)
        XCTAssertEqual(pool.implementation, "whales")

        // And the picker model scales min_stake to human TON.
        let model = TonStakingPool(entry: pool, decimals: 9)
        XCTAssertEqual(model.minStake, 50)
        XCTAssertTrue(model.hasCapacity)
    }
}
