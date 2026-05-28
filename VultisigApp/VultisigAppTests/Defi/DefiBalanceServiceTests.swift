//
//  DefiBalanceServiceTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class DefiBalanceServiceTests: XCTestCase {
    private var storeToken: TestContextToken!
    private var vault: Vault!
    private let service = DefiBalanceService()

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
        vault = TestStore.makeVault()
    }

    override func tearDown() async throws {
        vault = nil
        TestStore.restore(storeToken)
        storeToken = nil
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

    // MARK: - Tron (issue #4284)

    func testTronCoinDefiBalanceDecimalReturnsStakedNotWallet() {
        // 100 TRX wallet, 5 TRX frozen. Pre-fix this returned 100 (the bug).
        let trx = makeTronCoin(rawBalance: "100000000", stakedBalance: "5000000")
        XCTAssertEqual(trx.balanceDecimal, 100)
        XCTAssertEqual(trx.stakedBalanceDecimal, 5)
        XCTAssertEqual(trx.defiBalanceDecimal, 5, "Tron DeFi crypto subtitle must reflect frozen TRX, not wallet TRX.")
    }

    func testTronTotalBalanceFiatReadsStakedNotWallet() throws {
        // Register a 0.5 USD/TRX rate so we can distinguish staked × rate from wallet × rate.
        let trx = makeTronCoin(rawBalance: "100000000", stakedBalance: "5000000")
        vault.coins = [trx]
        try RateProvider.shared.save(rates: [
            Rate(fiat: SettingsCurrency.current.rawValue, crypto: "tron", value: 0.5)
        ])

        let total = service.totalBalanceInFiat(for: .tron, vault: vault)
        XCTAssertEqual(total, Decimal(5) * Decimal(0.5), "Tron DeFi fiat must be staked × rate, not wallet × rate.")
        XCTAssertNotEqual(total, Decimal(100) * Decimal(0.5), "Regression guard: must NOT equal wallet × rate.")
    }

    func testTronTotalBalanceFiatZeroWhenNoTronCoin() {
        XCTAssertEqual(service.totalBalanceInFiat(for: .tron, vault: vault), .zero)
    }

    private func makeTronCoin(rawBalance: String, stakedBalance: String) -> Coin {
        let trxMeta = CoinMeta.make(chain: .tron, ticker: "TRX", decimals: 6)
        let coin = Coin(asset: trxMeta, address: "TTronTestAddress", hexPublicKey: "")
        coin.priceProviderId = "tron"
        coin.rawBalance = rawBalance
        coin.stakedBalance = stakedBalance
        return coin
    }

    // MARK: - Position counts (Windows parity)

    func testPositionCountZeroForEmptyVault() {
        XCTAssertEqual(service.defiPositionCount(for: .thorChain, vault: vault), 0)
        XCTAssertEqual(service.defiPositionCount(for: .mayaChain, vault: vault), 0)
        XCTAssertEqual(service.defiPositionCount(for: .tron, vault: vault), 0)
        XCTAssertEqual(service.defiPositionCount(for: .terra, vault: vault), 0)
        XCTAssertEqual(service.defiPositionCount(for: .terraClassic, vault: vault), 0)
    }

    func testThorchainPositionCountSumsEnabledBondAndStakePositions() throws {
        let runeMeta = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        let tcyMeta = CoinMeta.make(chain: .thorChain, ticker: "TCY")
        let rune = Coin(asset: runeMeta, address: "thor1abc", hexPublicKey: "")
        vault.coins = [rune]
        vault.defiPositions = [
            DefiPositions(chain: .thorChain, bonds: [runeMeta], staking: [tcyMeta], lps: [])
        ]
        let storage = DefiPositionsStorageService()
        try storage.upsert(stake: [
            StakePositionData(coin: tcyMeta, type: .stake, amount: 3),
            StakePositionData(coin: runeMeta, type: .stake, amount: 7)
        ], for: vault)

        let count = service.defiPositionCount(for: .thorChain, vault: vault)
        XCTAssertEqual(count, 1, "Only the TCY stake is enabled; the RUNE stake is not in `staking`.")
    }

    func testThorchainPositionCountZeroWhenChainNotEnabled() {
        XCTAssertEqual(service.defiPositionCount(for: .thorChain, vault: vault), 0)
    }

    func testTronPositionCountOneWhenAnyTrxFrozen() {
        let trx = makeTronCoin(rawBalance: "0", stakedBalance: "1")
        vault.coins = [trx]
        XCTAssertEqual(service.defiPositionCount(for: .tron, vault: vault), 1)
    }

    func testTronPositionCountZeroWhenNoFrozenTrx() {
        let trx = makeTronCoin(rawBalance: "100000000", stakedBalance: "0")
        vault.coins = [trx]
        XCTAssertEqual(service.defiPositionCount(for: .tron, vault: vault), 0)
    }

    func testTerraPositionCountMatchesStakePositionsForChain() throws {
        let lunaMeta = CoinMeta.make(chain: .terra, ticker: "LUNA")
        let luna = Coin(asset: lunaMeta, address: "terra1abc", hexPublicKey: "")
        vault.coins = [luna]
        vault.defiPositions = [
            DefiPositions(chain: .terra, bonds: [], staking: [lunaMeta], lps: [])
        ]
        let storage = DefiPositionsStorageService()
        try storage.upsert(stake: [
            StakePositionData(coin: lunaMeta, type: .stake, amount: 1)
        ], for: vault)

        XCTAssertEqual(service.defiPositionCount(for: .terra, vault: vault), 1)
    }

    func testTerraPositionCountZeroWhenStakingNotEnabled() throws {
        let lunaMeta = CoinMeta.make(chain: .terra, ticker: "LUNA")
        let luna = Coin(asset: lunaMeta, address: "terra1abc", hexPublicKey: "")
        vault.coins = [luna]
        vault.defiPositions = [
            DefiPositions(chain: .terra, bonds: [], staking: [], lps: [])
        ]
        let storage = DefiPositionsStorageService()
        try storage.upsert(stake: [
            StakePositionData(coin: lunaMeta, type: .stake, amount: 1)
        ], for: vault)

        XCTAssertEqual(service.defiPositionCount(for: .terra, vault: vault), 0)
    }
}
