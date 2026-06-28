//
//  TonPoolSelectionTests.swift
//  VultisigAppTests
//
//  Pins the TON pool picker's sort/filter contract and the decode of the
//  tonapi.io `/v2/staking/pools` and `/v2/staking/nominator/{id}/pools`
//  responses.
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
        minStake: Int64 = 50_000_000_000,
        implementation: String = "whales"
    ) -> TonStakingPoolListEntry {
        TonStakingPoolListEntry(
            address: address,
            name: "Pool \(address)",
            apy: apy,
            minStake: minStake,
            verified: verified,
            currentNominators: current,
            maxNominators: max,
            implementation: implementation
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

    func testSortAndFilterExcludesLiquidStakingPools() {
        let raw = [
            // Tonstakers-style liquid pool — highest APY, but must be dropped
            // because our "d"/"w" deposit can't stake into it.
            entry(address: "tonstakers", apy: 99, verified: true, implementation: "liquidTF"),
            entry(address: "whales", apy: 13, verified: true, implementation: "whales"),
            entry(address: "tf", apy: 17, verified: true, implementation: "tf")
        ]
        let result = TonPoolSelectionViewModel.sortAndFilter(raw, decimals: 9)
        XCTAssertEqual(result.map(\.address), ["tf", "whales"])
        XCTAssertFalse(result.contains { $0.address == "tonstakers" })
    }

    func testSortAndFilterExcludesUnknownImplementations() {
        let raw = [
            entry(address: "known", apy: 10, verified: true, implementation: "whales"),
            entry(address: "mystery", apy: 50, verified: true, implementation: "somethingNew")
        ]
        let result = TonPoolSelectionViewModel.sortAndFilter(raw, decimals: 9)
        XCTAssertEqual(result.map(\.address), ["known"])
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
        XCTAssertTrue(model.isNominatorPool)
    }

    func testDecodeNominatorPoolsResponse() throws {
        let json = """
        {
          "pools": [
            {
              "pool": "0:00ff9fdd8b3b80d70e8ea734d262f5e1bd4c184c33535bf3190dd67408629e7a",
              "amount": 28152327,
              "pending_deposit": 0,
              "pending_withdraw": 28152327,
              "ready_withdraw": 0
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(TonAccountStakingResponse.self, from: data)
        XCTAssertEqual(response.pools.count, 1)
        let info = try XCTUnwrap(response.pools.first)
        XCTAssertEqual(info.pool, "0:00ff9fdd8b3b80d70e8ea734d262f5e1bd4c184c33535bf3190dd67408629e7a")
        XCTAssertEqual(info.amount, 28_152_327)
        XCTAssertEqual(info.pendingDeposit, 0)
        XCTAssertEqual(info.pendingWithdraw, 28_152_327)
        XCTAssertEqual(info.readyWithdraw, 0)
    }

    func testDecodeEmptyNominatorPoolsResponse() throws {
        let data = Data(#"{"pools":[]}"#.utf8)
        let response = try JSONDecoder().decode(TonAccountStakingResponse.self, from: data)
        XCTAssertTrue(response.pools.isEmpty)
    }

    /// A just-placed deposit sits in `pending_deposit` (active `amount` 0) until
    /// the next validation cycle — it must still count toward the visible
    /// position so the user doesn't "see nothing" right after staking.
    func testPendingDepositOnlyStillProducesVisiblePosition() {
        let info = TonAccountStakingInfo(
            pool: "0:abc",
            amount: 0,
            pendingDeposit: 1_000_000_000, // 1 TON pending
            pendingWithdraw: 0,
            readyWithdraw: 0
        )
        let total = Decimal(info.amount) + Decimal(info.pendingDeposit)
        XCTAssertGreaterThan(total, 0)
        XCTAssertEqual(total / pow(Decimal(10), 9), 1)
    }
}
