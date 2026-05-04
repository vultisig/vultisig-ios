//
//  DefiPositionsStorageServiceTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class DefiPositionsStorageServiceTests: XCTestCase {
    private var storeToken: DefiTestContextToken!
    private var vault: Vault!
    private let service = DefiPositionsStorageService()

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try DefiTestStore.installInMemoryContainer()
        vault = DefiTestStore.makeVault()
    }

    override func tearDown() async throws {
        vault = nil
        DefiTestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    // MARK: - Stake upsert

    func testUpsertStakeInsertsNewPosition() throws {
        let runeMeta = CoinMeta.make(chain: .thorChain, ticker: "RUNE")

        let materialized = try service.upsert(stake: [
            StakePositionData(coin: runeMeta, type: .stake, amount: 10)
        ], for: vault)

        XCTAssertEqual(materialized.count, 1)
        XCTAssertEqual(materialized.first?.amount, 10)
        XCTAssertEqual(vault.stakePositions.count, 1)
    }

    func testUpsertStakeUpdatesExistingInPlace() throws {
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

    func testUpsertStakeOmittedDtoLeavesPersistedRowUntouched() throws {
        let runeMeta = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        let tcyMeta = CoinMeta.make(chain: .thorChain, ticker: "TCY")

        _ = try service.upsert(stake: [
            StakePositionData(coin: runeMeta, type: .stake, amount: 10),
            StakePositionData(coin: tcyMeta, type: .stake, amount: 20)
        ], for: vault)

        // Refresh succeeds for RUNE only — TCY's per-coin fetch failed and was omitted.
        // The persisted TCY row must stay untouched.
        _ = try service.upsert(stake: [
            StakePositionData(coin: runeMeta, type: .stake, amount: 15)
        ], for: vault)

        XCTAssertEqual(vault.stakePositions.count, 2)
        XCTAssertEqual(vault.stakePositions.first(where: { $0.coin.ticker == "RUNE" })?.amount, 15)
        XCTAssertEqual(vault.stakePositions.first(where: { $0.coin.ticker == "TCY" })?.amount, 20)
    }

    // MARK: - LP upsert

    func testUpsertLpInsertsNewPosition() throws {
        let rune = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        let btc = CoinMeta.make(chain: .bitcoin, ticker: "BTC")

        let materialized = try service.upsert(lp: [
            LPPositionData(coin1: rune, coin1Amount: 100, coin2: btc, coin2Amount: 1, poolName: "BTC.BTC", poolUnits: "10", apr: 0.04)
        ], for: vault)

        XCTAssertEqual(materialized.count, 1)
        XCTAssertEqual(vault.lpPositions.count, 1)
    }

    func testUpsertLpUpdatesExistingInPlace() throws {
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
        XCTAssertEqual(materialized.first?.apr, 0.08)
    }

    func testUpsertLpOmittedDtoLeavesPersistedRowUntouched() throws {
        let rune = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        let btc = CoinMeta.make(chain: .bitcoin, ticker: "BTC")
        let eth = CoinMeta.make(chain: .ethereum, ticker: "ETH")

        _ = try service.upsert(lp: [
            LPPositionData(coin1: rune, coin1Amount: 1, coin2: btc, coin2Amount: 1, poolName: "BTC.BTC", poolUnits: "1", apr: 0.04),
            LPPositionData(coin1: rune, coin1Amount: 2, coin2: eth, coin2Amount: 2, poolName: "ETH.ETH", poolUnits: "2", apr: 0.05)
        ], for: vault)

        // Partial refresh — BTC missing from input. Persisted BTC row stays.
        _ = try service.upsert(lp: [
            LPPositionData(coin1: rune, coin1Amount: 3, coin2: eth, coin2Amount: 3, poolName: "ETH.ETH", poolUnits: "3", apr: 0.06)
        ], for: vault)

        XCTAssertEqual(vault.lpPositions.count, 2)
        XCTAssertEqual(Set(vault.lpPositions.map { $0.coin2.ticker }), ["BTC", "ETH"])
    }

    // MARK: - Enable / disable

    func testAddZeroStakeInsertsZeroRow() throws {
        let runeMeta = CoinMeta.make(chain: .thorChain, ticker: "RUNE")

        try service.addZero(stakeCoin: runeMeta, to: vault)

        XCTAssertEqual(vault.stakePositions.count, 1)
        XCTAssertEqual(vault.stakePositions.first?.amount, 0)
        XCTAssertEqual(vault.stakePositions.first?.coin.ticker, "RUNE")
    }

    func testAddZeroStakeIsIdempotent() throws {
        let runeMeta = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        _ = try service.upsert(stake: [
            StakePositionData(coin: runeMeta, type: .stake, amount: 42)
        ], for: vault)

        try service.addZero(stakeCoin: runeMeta, to: vault)

        XCTAssertEqual(vault.stakePositions.count, 1)
        XCTAssertEqual(vault.stakePositions.first?.amount, 42, "Existing row must not be clobbered.")
    }

    func testRemoveStakeDeletesRow() throws {
        let runeMeta = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        try service.addZero(stakeCoin: runeMeta, to: vault)
        XCTAssertEqual(vault.stakePositions.count, 1)

        try service.removeStake(coin: runeMeta, from: vault)

        XCTAssertEqual(vault.stakePositions.count, 0)
    }

    func testAddZeroLpInsertsZeroRow() throws {
        let runeMeta = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        let btcMeta = CoinMeta.make(chain: .bitcoin, ticker: "BTC")

        try service.addZero(lpCoin2: btcMeta, nativeCoin: runeMeta, to: vault)

        XCTAssertEqual(vault.lpPositions.count, 1)
        XCTAssertEqual(vault.lpPositions.first?.coin1Amount, 0)
        XCTAssertEqual(vault.lpPositions.first?.coin2.ticker, "BTC")
    }

    func testRemoveLpDeletesRow() throws {
        let runeMeta = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        let btcMeta = CoinMeta.make(chain: .bitcoin, ticker: "BTC")
        try service.addZero(lpCoin2: btcMeta, nativeCoin: runeMeta, to: vault)
        XCTAssertEqual(vault.lpPositions.count, 1)

        try service.removeLP(coin2: btcMeta, from: vault)

        XCTAssertEqual(vault.lpPositions.count, 0)
    }

    func testLpZeroPlaceholderMergesWithApiPoolName() throws {
        let runeMeta = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        let usdcMeta = CoinMeta.make(chain: .ethereum, ticker: "USDC")

        // Enable: zero placeholder with synthesized poolName.
        try service.addZero(lpCoin2: usdcMeta, nativeCoin: runeMeta, to: vault)

        // Refresh: API returns canonical poolName with contract suffix. Same coin2 ⇒ merge.
        _ = try service.upsert(lp: [
            LPPositionData(
                coin1: runeMeta,
                coin1Amount: 100,
                coin2: usdcMeta,
                coin2Amount: 50,
                poolName: "ETH.USDC-0xabc",
                poolUnits: "10",
                apr: 0.07
            )
        ], for: vault)

        XCTAssertEqual(vault.lpPositions.count, 1, "Placeholder must merge with API row, not duplicate.")
        XCTAssertEqual(vault.lpPositions.first?.coin1Amount, 100)
        XCTAssertEqual(vault.lpPositions.first?.poolName, "ETH.USDC-0xabc")
    }

    // MARK: - Notifications

    func testUpsertStakePostsDidChangeNotification() async throws {
        let expectation = expectation(forNotification: .defiPositionsDidChange, object: nil)

        try service.upsert(stake: [
            StakePositionData(coin: .make(chain: .thorChain, ticker: "RUNE"), type: .stake, amount: 1)
        ], for: vault)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testUpsertLpPostsDidChangeNotification() async throws {
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
}
