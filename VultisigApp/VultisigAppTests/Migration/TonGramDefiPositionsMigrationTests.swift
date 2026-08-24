//
//  TonGramDefiPositionsMigrationTests.swift
//  VultisigAppTests
//

import XCTest
import SwiftData
@testable import VultisigApp

@MainActor
final class TonGramDefiPositionsMigrationTests: XCTestCase {
    private var token: TestContextToken?

    override func setUpWithError() throws {
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDownWithError() throws {
        TestStore.restore(token)
        token = nil
    }

    // MARK: - Fixtures

    /// A pre-rebrand native TON meta, exactly as vaults persisted it before the
    /// Toncoin → Gram rename.
    private func legacyTonMeta() -> CoinMeta {
        CoinMeta(
            chain: .ton,
            ticker: "TON",
            logo: "ton",
            decimals: 9,
            priceProviderId: "the-open-network",
            contractAddress: "",
            isNativeToken: true
        )
    }

    /// Builds a vault with unique values for EVERY `@Attribute(.unique)` field.
    /// `TestStore.makeVault` varies only `pubKeyECDSA`, so two of its vaults in
    /// one test collapse into a single row via the unique `pubKeyEdDSA` — and a
    /// migration that walks every vault has to be exercised across more than one.
    private func makeVault() -> Vault {
        let id = UUID().uuidString
        let vault = Vault(
            name: "Test Vault \(id)",
            signers: [],
            pubKeyECDSA: "ecdsa-\(id)",
            pubKeyEdDSA: "eddsa-\(id)",
            keyshares: [],
            localPartyID: "party",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
        Storage.shared.modelContext.insert(vault)
        return vault
    }

    @discardableResult
    private func makeDefiPositions(
        for vault: Vault,
        chain: Chain = .ton,
        bonds: [CoinMeta] = [],
        staking: [CoinMeta] = [],
        lps: [CoinMeta] = []
    ) -> DefiPositions {
        let positions = DefiPositions(chain: chain, bonds: bonds, staking: staking, lps: lps)
        vault.defiPositions.append(positions)
        return positions
    }

    @discardableResult
    private func makeStakePosition(
        for vault: Vault,
        coin: CoinMeta,
        rewardCoin: CoinMeta? = nil
    ) -> StakePosition {
        let position = StakePosition(
            coin: coin,
            type: .stake,
            amount: 42,
            rewardCoin: rewardCoin,
            vault: vault
        )
        Storage.shared.modelContext.insert(position)
        return position
    }

    // MARK: - Rewrites

    func testMigratesNativeTonMetaInEveryDefiPositionArray() throws {
        let vault = makeVault()
        let positions = makeDefiPositions(
            for: vault,
            bonds: [legacyTonMeta()],
            staking: [legacyTonMeta()],
            lps: [legacyTonMeta()]
        )
        try Storage.shared.save()

        try TonGramDefiPositionsMigration().migrate()

        for array in [positions.bonds, positions.staking, positions.lps] {
            XCTAssertEqual(array.first?.ticker, "GRAM")
            XCTAssertEqual(array.first?.logo, "ton")
        }
    }

    /// Everything that identifies the coin must survive the rebrand — only the
    /// two display fields move.
    func testPreservesEveryIdentifyingField() throws {
        let vault = makeVault()
        let positions = makeDefiPositions(for: vault, staking: [legacyTonMeta()])
        try Storage.shared.save()

        try TonGramDefiPositionsMigration().migrate()

        let migrated = try XCTUnwrap(positions.staking.first)
        XCTAssertEqual(migrated.chain, .ton)
        XCTAssertEqual(migrated.decimals, 9)
        XCTAssertEqual(migrated.priceProviderId, "the-open-network")
        XCTAssertEqual(migrated.contractAddress, "")
        XCTAssertTrue(migrated.isNativeToken)
    }

    func testMigratesStakePositionCoinAndRewardCoin() throws {
        let vault = makeVault()
        let position = makeStakePosition(
            for: vault,
            coin: legacyTonMeta(),
            rewardCoin: legacyTonMeta()
        )
        try Storage.shared.save()

        try TonGramDefiPositionsMigration().migrate()

        XCTAssertEqual(position.coin.ticker, "GRAM")
        XCTAssertEqual(position.coin.logo, "ton")
        XCTAssertEqual(position.rewardCoin?.ticker, "GRAM")
        XCTAssertEqual(position.rewardCoin?.logo, "ton")
    }

    /// `StakePosition.id` is `@Attribute(.unique)` and is built from
    /// `coin.chain.ticker` — the chain's protocol identifier, which stays "TON".
    /// If the migration ever moved it, SwiftData would silently merge or orphan
    /// the row instead of rebranding it.
    func testLeavesTheUniqueStakePositionIDUntouched() throws {
        let vault = makeVault()
        let position = makeStakePosition(for: vault, coin: legacyTonMeta())
        try Storage.shared.save()
        let idBefore = position.id

        try TonGramDefiPositionsMigration().migrate()

        XCTAssertEqual(position.id, idBefore)
        XCTAssertEqual(
            position.id,
            StakePosition.makeID(coin: position.coin, vault: vault, stakeAccountPubkey: nil)
        )
    }

    func testMigratesEveryVault() throws {
        let first = makeVault()
        let second = makeVault()
        let firstPositions = makeDefiPositions(for: first, staking: [legacyTonMeta()])
        let secondPositions = makeDefiPositions(for: second, staking: [legacyTonMeta()])
        try Storage.shared.save()

        // Proves the two fixtures did not collapse through a shared unique
        // attribute — otherwise the assertions below would pass having exercised
        // a single vault.
        let stored = try Storage.shared.modelContext.fetch(FetchDescriptor<Vault>())
        XCTAssertEqual(stored.count, 2)

        try TonGramDefiPositionsMigration().migrate()

        XCTAssertEqual(firstPositions.staking.first?.ticker, "GRAM")
        XCTAssertEqual(secondPositions.staking.first?.ticker, "GRAM")
    }

    // MARK: - Leaves alone

    func testLeavesJettonsAndOtherChainsUntouched() throws {
        let vault = makeVault()
        // A TON-chain jetton is not the native coin and keeps its own identity.
        let jetton = CoinMeta(
            chain: .ton,
            ticker: "USDT",
            logo: "usdt",
            decimals: 6,
            priceProviderId: "tether",
            contractAddress: "EQjetton",
            isNativeToken: false
        )
        // A native coin on another chain is unaffected.
        let rune = CoinMeta(
            chain: .thorChain,
            ticker: "RUNE",
            logo: "rune",
            decimals: 8,
            priceProviderId: "thorchain",
            contractAddress: "",
            isNativeToken: true
        )
        let positions = makeDefiPositions(for: vault, chain: .thorChain, staking: [jetton, rune])
        let stake = makeStakePosition(for: vault, coin: rune)
        try Storage.shared.save()

        try TonGramDefiPositionsMigration().migrate()

        XCTAssertEqual(positions.staking.first?.ticker, "USDT")
        XCTAssertEqual(positions.staking.first?.logo, "usdt")
        XCTAssertEqual(positions.staking.last?.ticker, "RUNE")
        XCTAssertEqual(positions.staking.last?.logo, "rune")
        XCTAssertEqual(stake.coin.ticker, "RUNE")
    }

    /// A vault that never opted into a DeFi position must be a no-op, not a
    /// throw — the migration runs on every install at launch.
    func testVaultWithoutAnyPositionsIsUntouched() throws {
        let vault = makeVault()
        try Storage.shared.save()

        XCTAssertNoThrow(try TonGramDefiPositionsMigration().migrate())

        XCTAssertTrue(vault.defiPositions.isEmpty)
        XCTAssertTrue(vault.stakePositions.isEmpty)
    }

    /// An already-migrated vault (or a fresh install that never held "TON") must
    /// survive a second pass unchanged.
    func testIsIdempotent() throws {
        let vault = makeVault()
        let positions = makeDefiPositions(for: vault, staking: [legacyTonMeta()])
        let stake = makeStakePosition(for: vault, coin: legacyTonMeta(), rewardCoin: legacyTonMeta())
        try Storage.shared.save()

        try TonGramDefiPositionsMigration().migrate()
        let idAfterFirstPass = stake.id
        try TonGramDefiPositionsMigration().migrate()

        XCTAssertEqual(positions.staking.count, 1)
        XCTAssertEqual(positions.staking.first?.ticker, "GRAM")
        XCTAssertEqual(positions.staking.first?.logo, "ton")
        XCTAssertEqual(stake.coin.ticker, "GRAM")
        XCTAssertEqual(stake.rewardCoin?.ticker, "GRAM")
        XCTAssertEqual(stake.id, idAfterFirstPass)
    }

    // MARK: - Registration

    /// The version must be unique and ordered after the migrations already
    /// shipped, otherwise `AppMigrationService`'s Keychain watermark either skips
    /// it or re-runs an unrelated migration.
    func testVersionIsUniqueAndHighest() throws {
        let migration = TonGramDefiPositionsMigration()
        let others = [
            THORChainDuplicateTokensMigration().version,
            TonGramRebrandMigration().version,
            PromoBannerDismissalMigration().version,
            RujiAutoCompoundPositionMigration().version
        ]

        XCTAssertFalse(others.contains(migration.version))
        XCTAssertGreaterThan(migration.version, try XCTUnwrap(others.max()))
    }
}
