//
//  DefiPositionsStorageServiceTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class DefiPositionsStorageServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var vault: Vault!
    private let service = DefiPositionsStorageService()

    override func setUp() async throws {
        try await super.setUp()
        container = try DefiTestStore.makeInMemoryContainer()
        vault = DefiTestStore.makeVault()
    }

    override func tearDown() async throws {
        vault = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Stake upsert

    func test_upsert_stake_inserts_new_position() throws {
        let runeMeta = CoinMeta.make(chain: .thorChain, ticker: "RUNE")

        let materialized = try service.upsert(stake: [
            StakePositionData(coin: runeMeta, type: .stake, amount: 10)
        ], for: vault)

        XCTAssertEqual(materialized.count, 1)
        XCTAssertEqual(materialized.first?.amount, 10)
        XCTAssertEqual(vault.stakePositions.count, 1, "Inverse relationship should attach the materialized model.")
    }

    func test_upsert_stake_updates_existing_in_place() throws {
        let runeMeta = CoinMeta.make(chain: .thorChain, ticker: "RUNE")

        _ = try service.upsert(stake: [
            StakePositionData(coin: runeMeta, type: .stake, amount: 10)
        ], for: vault)

        let materialized = try service.upsert(stake: [
            StakePositionData(coin: runeMeta, type: .stake, amount: 25, apr: 0.12)
        ], for: vault)

        XCTAssertEqual(materialized.count, 1)
        XCTAssertEqual(vault.stakePositions.count, 1, "Same id ⇒ updated in place, no new row.")
        XCTAssertEqual(materialized.first?.amount, 25)
        XCTAssertEqual(materialized.first?.apr, 0.12)
    }

    func test_upsert_stake_returns_models_in_dto_order() throws {
        let runeMeta = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        let tcyMeta = CoinMeta.make(chain: .thorChain, ticker: "TCY")

        let materialized = try service.upsert(stake: [
            StakePositionData(coin: runeMeta, type: .stake, amount: 1),
            StakePositionData(coin: tcyMeta, type: .stake, amount: 2)
        ], for: vault)

        XCTAssertEqual(materialized.map(\.coin.ticker), ["RUNE", "TCY"])
    }

    // MARK: - LP upsert

    func test_upsert_lp_inserts_new_position() throws {
        let rune = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        let btc = CoinMeta.make(chain: .bitcoin, ticker: "BTC")

        let materialized = try service.upsert(lp: [
            LPPositionData(coin1: rune, coin1Amount: 100, coin2: btc, coin2Amount: 1, poolName: "BTC.BTC", poolUnits: "10", apr: 0.04)
        ], for: vault)

        XCTAssertEqual(materialized.count, 1)
        XCTAssertEqual(vault.lpPositions.count, 1)
        XCTAssertEqual(materialized.first?.coin2.ticker, "BTC")
    }

    func test_upsert_lp_updates_existing_in_place() throws {
        let rune = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        let btc = CoinMeta.make(chain: .bitcoin, ticker: "BTC")

        _ = try service.upsert(lp: [
            LPPositionData(coin1: rune, coin1Amount: 100, coin2: btc, coin2Amount: 1, poolName: "BTC.BTC", poolUnits: "10", apr: 0.04)
        ], for: vault)

        let materialized = try service.upsert(lp: [
            LPPositionData(coin1: rune, coin1Amount: 200, coin2: btc, coin2Amount: 2, poolName: "BTC.BTC", poolUnits: "20", apr: 0.08)
        ], for: vault)

        XCTAssertEqual(vault.lpPositions.count, 1)
        XCTAssertEqual(materialized.first?.coin1Amount, 200)
        XCTAssertEqual(materialized.first?.coin2Amount, 2)
        XCTAssertEqual(materialized.first?.apr, 0.08)
    }

    // MARK: - Notifications

    func test_upsert_stake_posts_did_change_notification() async throws {
        let expectation = expectation(forNotification: .defiPositionsDidChange, object: nil)

        try service.upsert(stake: [
            StakePositionData(coin: .make(chain: .thorChain, ticker: "RUNE"), type: .stake, amount: 1)
        ], for: vault)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func test_upsert_lp_posts_did_change_notification() async throws {
        let expectation = expectation(forNotification: .defiPositionsDidChange, object: nil)

        try service.upsert(lp: [
            LPPositionData(
                coin1: .make(chain: .thorChain, ticker: "RUNE"),
                coin1Amount: 1,
                coin2: .make(chain: .bitcoin, ticker: "BTC"),
                coin2Amount: 1,
                poolName: "BTC.BTC",
                poolUnits: "1",
                apr: 0.04
            )
        ], for: vault)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    // MARK: - Empty input

    func test_upsert_stake_empty_array_does_not_modify_storage() throws {
        let runeMeta = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        _ = try service.upsert(stake: [
            StakePositionData(coin: runeMeta, type: .stake, amount: 1)
        ], for: vault)

        XCTAssertEqual(vault.stakePositions.count, 1)

        // Confirm Stake upsert does NOT delete-stale (asymmetric with Bond — documented).
        _ = try service.upsert(stake: [], for: vault)
        XCTAssertEqual(vault.stakePositions.count, 1, "Stake upsert with [] must NOT delete persisted positions; only Bond does delete-stale.")
    }

    func test_upsert_lp_empty_array_does_not_modify_storage() throws {
        let rune = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        let btc = CoinMeta.make(chain: .bitcoin, ticker: "BTC")
        _ = try service.upsert(lp: [
            LPPositionData(coin1: rune, coin1Amount: 1, coin2: btc, coin2Amount: 1, poolName: "BTC.BTC", poolUnits: "1", apr: 0.04)
        ], for: vault)

        XCTAssertEqual(vault.lpPositions.count, 1)

        _ = try service.upsert(lp: [], for: vault)
        XCTAssertEqual(vault.lpPositions.count, 1, "LP upsert with [] must NOT delete persisted positions.")
    }
}
