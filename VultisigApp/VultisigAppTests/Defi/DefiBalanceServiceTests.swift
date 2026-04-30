//
//  DefiBalanceServiceTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class DefiBalanceServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var vault: Vault!
    private let service = DefiBalanceService()

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

    // MARK: - Empty vault

    func testThorchainBalanceZeroWhenNoDefiPositions() {
        let total = service.totalBalanceInFiat(for: .thorChain, vault: vault)
        XCTAssertEqual(total, .zero)
    }

    func testMayachainBalanceZeroWhenNoDefiPositions() {
        let total = service.totalBalanceInFiat(for: .mayaChain, vault: vault)
        XCTAssertEqual(total, .zero)
    }

    func testDefaultChainBalanceZeroWhenNoMatchingCoins() {
        let total = service.totalBalanceInFiat(for: .ethereum, vault: vault)
        XCTAssertEqual(total, .zero)
    }

    // MARK: - Filter wiring

    func testThorchainBalanceWithDisabledChainReturnsZero() throws {
        // Without `defiPositions` containing .thorChain, the THORChain branch short-circuits.
        let storage = DefiPositionsStorageService()
        let runeMeta = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        try storage.upsert(stake: [
            StakePositionData(coin: runeMeta, type: .stake, amount: 5)
        ], for: vault)

        let total = service.totalBalanceInFiat(for: .thorChain, vault: vault)
        XCTAssertEqual(total, .zero, "No defiPositions entry for thorChain → short-circuits to zero before reading stake/bond/lp.")
    }

    func testThorchainPersistsStakeThroughStorage() throws {
        let runeMeta = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        let tcyMeta = CoinMeta.make(chain: .thorChain, ticker: "TCY")
        let storage = DefiPositionsStorageService()

        vault.defiPositions = [
            DefiPositions(chain: .thorChain, bonds: [], staking: [tcyMeta], lps: [])
        ]

        try storage.upsert(stake: [
            StakePositionData(coin: runeMeta, type: .stake, amount: 5),
            StakePositionData(coin: tcyMeta, type: .stake, amount: 3)
        ], for: vault)

        XCTAssertEqual(vault.stakePositions.count, 2)
    }

    // MARK: - Multi-chain string formatting

    func testBalanceStringForChainsReturnsFormattedZeroForNoPositions() {
        let total = service.totalBalanceInFiatString(for: [.thorChain, .mayaChain], vault: vault)
        XCTAssertFalse(total.isEmpty)
    }

    func testBalanceStringForSingleChainReturnsFormattedZero() {
        let total = service.totalBalanceInFiatString(for: .thorChain, vault: vault)
        XCTAssertFalse(total.isEmpty)
    }
}
