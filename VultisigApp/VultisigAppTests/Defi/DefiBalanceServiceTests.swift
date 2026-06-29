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

    func testTronTotalBalanceAndCountZeroWhenStakedBalanceUnset() throws {
        // Default `Coin.stakedBalance` is the empty string (never refreshed).
        // The DeFi main row must read $0.00 / 0 positions, not crash or inherit
        // the wallet balance — this is exactly the stale state issue #4608 hits.
        let trx = makeTronCoin(rawBalance: "100000000", stakedBalance: "")
        vault.coins = [trx]
        try RateProvider.shared.save(rates: [
            Rate(fiat: SettingsCurrency.current.rawValue, crypto: "tron", value: 0.5)
        ])

        XCTAssertEqual(service.totalBalanceInFiat(for: .tron, vault: vault), .zero)
        XCTAssertTrue(service.totalBalanceInFiatString(for: .tron, vault: vault).contains("0"))
        XCTAssertEqual(service.defiPositionCount(for: .tron, vault: vault), 0)
    }

    private func makeTronCoin(rawBalance: String, stakedBalance: String) -> Coin {
        let trxMeta = CoinMeta.make(chain: .tron, ticker: "TRX", decimals: 6)
        let coin = Coin(asset: trxMeta, address: "TTronTestAddress", hexPublicKey: "")
        coin.priceProviderId = "tron"
        coin.rawBalance = rawBalance
        coin.stakedBalance = stakedBalance
        return coin
    }

    // MARK: - TON nominator staking (issue #4653)

    /// A real TON nominator stake (surfaced as a `StakePosition`) must contribute
    /// to the DeFi total and count as a position WITHOUT enabling the per-coin
    /// opt-in (`defiPositions[.ton].staking`) — mirrors Tron.
    func testTonTotalBalanceFiatFromStakePositionWithoutOptIn() throws {
        let tonMeta = TokensStore.ton
        let ton = Coin(asset: tonMeta, address: "UQTonTestAddress", hexPublicKey: "")
        ton.priceProviderId = tonMeta.priceProviderId
        vault.coins = [ton]
        // No `defiPositions[.ton].staking` entry: the position must still count.
        try RateProvider.shared.save(rates: [
            Rate(fiat: SettingsCurrency.current.rawValue, crypto: tonMeta.priceProviderId, value: 2)
        ])

        let storage = DefiPositionsStorageService()
        try storage.upsert(stake: [
            StakePositionData(coin: tonMeta, type: .stake, amount: 10)
        ], for: vault)

        let total = service.totalBalanceInFiat(for: .ton, vault: vault)
        XCTAssertEqual(total, Decimal(10) * Decimal(2), "TON staked fiat must be staked amount × rate, ungated.")
    }

    func testTonPositionCountOneFromStakePositionWithoutOptIn() throws {
        let tonMeta = TokensStore.ton
        let ton = Coin(asset: tonMeta, address: "UQTonTestAddress", hexPublicKey: "")
        vault.coins = [ton]

        let storage = DefiPositionsStorageService()
        try storage.upsert(stake: [
            StakePositionData(coin: tonMeta, type: .stake, amount: 10)
        ], for: vault)

        XCTAssertEqual(service.defiPositionCount(for: .ton, vault: vault), 1, "A staked TON position counts without opt-in.")
    }

    func testTonPositionCountZeroWhenNoStake() {
        XCTAssertEqual(service.defiPositionCount(for: .ton, vault: vault), 0)
        XCTAssertEqual(service.totalBalanceInFiat(for: .ton, vault: vault), .zero)
    }

    func testTonPositionCountZeroWhenStakedAmountZero() throws {
        let tonMeta = TokensStore.ton
        let storage = DefiPositionsStorageService()
        try storage.upsert(stake: [
            StakePositionData(coin: tonMeta, type: .stake, amount: 0)
        ], for: vault)

        XCTAssertEqual(service.defiPositionCount(for: .ton, vault: vault), 0, "A zero-amount placeholder is not a position.")
    }

    // MARK: - Solana native staking

    private func makeSolanaCoin(rawBalance: String, stakedBalance: String) -> Coin {
        let solMeta = CoinMeta.make(chain: .solana, ticker: "SOL", decimals: 9)
        let coin = Coin(asset: solMeta, address: "SoLTestAddress", hexPublicKey: "")
        coin.priceProviderId = "solana"
        coin.rawBalance = rawBalance
        coin.stakedBalance = stakedBalance
        return coin
    }

    /// Staked SOL (summed delegated lamports written to `Coin.stakedBalance`)
    /// rolls into the DeFi total ungated — like Tron, no per-coin opt-in.
    func testSolanaTotalBalanceFiatReadsStakedNotWallet() throws {
        // 10 SOL wallet, 4 SOL delegated.
        let sol = makeSolanaCoin(rawBalance: "10000000000", stakedBalance: "4000000000")
        vault.coins = [sol]
        try RateProvider.shared.save(rates: [
            Rate(fiat: SettingsCurrency.current.rawValue, crypto: "solana", value: 3)
        ])

        let total = service.totalBalanceInFiat(for: .solana, vault: vault)
        XCTAssertEqual(total, Decimal(4) * Decimal(3), "Solana DeFi fiat must be delegated SOL × rate, not wallet × rate.")
        XCTAssertNotEqual(total, Decimal(10) * Decimal(3))
    }

    func testSolanaTotalBalanceFiatZeroWhenNoSolanaCoin() {
        XCTAssertEqual(service.totalBalanceInFiat(for: .solana, vault: vault), .zero)
    }

    func testSolanaTotalBalanceZeroWhenStakedBalanceUnset() throws {
        let sol = makeSolanaCoin(rawBalance: "10000000000", stakedBalance: "")
        vault.coins = [sol]
        try RateProvider.shared.save(rates: [
            Rate(fiat: SettingsCurrency.current.rawValue, crypto: "solana", value: 3)
        ])

        XCTAssertEqual(service.totalBalanceInFiat(for: .solana, vault: vault), .zero)
        XCTAssertEqual(service.defiPositionCount(for: .solana, vault: vault), 0)
    }

    func testSolanaPositionCountOneWhenAnyStaked() {
        let sol = makeSolanaCoin(rawBalance: "0", stakedBalance: "1")
        vault.coins = [sol]
        XCTAssertEqual(service.defiPositionCount(for: .solana, vault: vault), 1)
    }

    func testSolanaPositionCountZeroWhenNoStake() {
        let sol = makeSolanaCoin(rawBalance: "10000000000", stakedBalance: "0")
        vault.coins = [sol]
        XCTAssertEqual(service.defiPositionCount(for: .solana, vault: vault), 0)
    }

    /// The staking position picker resolves native SOL (no `TokensStore.sol`
    /// static) from `TokenSelectionAssets`.
    func testSolanaStakeCoinsResolvesNativeSol() {
        let coins = DefiPositionsService().stakeCoins(for: .solana)
        XCTAssertEqual(coins.count, 1)
        let sol = try? XCTUnwrap(coins.first)
        XCTAssertEqual(sol?.chain, .solana)
        XCTAssertEqual(sol?.ticker, "SOL")
        XCTAssertEqual(sol?.isNativeToken, true)
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
