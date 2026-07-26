//
//  RujiAutoCompoundPositionMigrationTests.swift
//  VultisigAppTests
//
//  RUJI's auto-compounding position used to live under the single "RUJI"
//  toggle. Now that it is its own selectable position, a vault that was already
//  auto-compounding would lose its card until the user discovered the new sRUJI
//  entry — so the migration opts those vaults in. These pin that it opts in
//  exactly once, and only where it should.
//

import SwiftData
import XCTest
@testable import VultisigApp

@MainActor
final class RujiAutoCompoundPositionMigrationTests: XCTestCase {
    private var token: TestContextToken?

    override func setUpWithError() throws {
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDownWithError() throws {
        TestStore.restore(token)
        token = nil
    }

    /// Builds a vault with unique values for EVERY `@Attribute(.unique)` field.
    /// `TestStore.makeVault` varies only `pubKeyECDSA`, so two of its vaults in
    /// one test collapse into a single row via the unique `pubKeyEdDSA` — and
    /// this migration has to be exercised across several vaults at once.
    private func makeVault(staking: [CoinMeta], chain: Chain = .thorChain) throws -> Vault {
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
        vault.defiPositions.append(DefiPositions(chain: chain, bonds: [], staking: staking, lps: []))
        try Storage.shared.save()
        return vault
    }

    private func stakingTickers(_ vault: Vault, chain: Chain = .thorChain) -> [String] {
        (vault.defiPositions.first { $0.chain == chain }?.staking ?? [])
            .map { $0.ticker.uppercased() }
            .sorted()
    }

    func testEnablesSRujiForVaultsTrackingRuji() throws {
        let vault = try makeVault(staking: [TokensStore.ruji])

        try RujiAutoCompoundPositionMigration().migrate()

        XCTAssertEqual(stakingTickers(vault), ["RUJI", "SRUJI"])
        XCTAssertTrue(
            vault.defiPositions.first { $0.chain == .thorChain }?.staking
                .contains { $0.contractAddress == "x/staking-x/ruji" } ?? false,
            "sRUJI must be added under its real on-chain denom"
        )
    }

    func testIsIdempotent() throws {
        let vault = try makeVault(staking: [TokensStore.ruji])

        try RujiAutoCompoundPositionMigration().migrate()
        try RujiAutoCompoundPositionMigration().migrate()

        XCTAssertEqual(stakingTickers(vault), ["RUJI", "SRUJI"])
    }

    /// The contains-check is what keeps a deliberate opt-out from being undone.
    func testLeavesVaultsThatAlreadyTrackSRujiAlone() throws {
        let vault = try makeVault(staking: [TokensStore.ruji, TokensStore.sruji])

        try RujiAutoCompoundPositionMigration().migrate()

        XCTAssertEqual(stakingTickers(vault), ["RUJI", "SRUJI"])
    }

    func testLeavesVaultsWithoutRujiAlone() throws {
        let vault = try makeVault(staking: [TokensStore.tcy])

        try RujiAutoCompoundPositionMigration().migrate()

        XCTAssertEqual(stakingTickers(vault), ["TCY"])
    }

    func testLeavesVaultsWithoutAnyThorchainPositionsAlone() throws {
        let vault = TestStore.makeVault()
        try Storage.shared.save()

        try RujiAutoCompoundPositionMigration().migrate()

        XCTAssertTrue(vault.defiPositions.isEmpty)
    }

    func testMigratesEveryVaultIndependently() throws {
        let withRuji = try makeVault(staking: [TokensStore.ruji])
        let withoutRuji = try makeVault(staking: [TokensStore.tcy])

        try RujiAutoCompoundPositionMigration().migrate()

        XCTAssertEqual(stakingTickers(withRuji), ["RUJI", "SRUJI"])
        XCTAssertEqual(stakingTickers(withoutRuji), ["TCY"])
    }

    /// The migration only widens the position list; it must not touch the other
    /// chains' selections.
    func testDoesNotTouchOtherChains() throws {
        let vault = try makeVault(staking: [TokensStore.cacao], chain: .mayaChain)
        vault.defiPositions.append(
            DefiPositions(chain: .thorChain, bonds: [], staking: [TokensStore.ruji], lps: [])
        )
        try Storage.shared.save()

        try RujiAutoCompoundPositionMigration().migrate()

        XCTAssertEqual(stakingTickers(vault, chain: .mayaChain), ["CACAO"])
        XCTAssertEqual(stakingTickers(vault), ["RUJI", "SRUJI"])
    }

    /// Registered with `AppMigrationService`, so it actually runs on launch —
    /// driven through the real service with a seeded version so only migrations
    /// newer than the shipped ones execute.
    func testIsRunByTheMigrationService() throws {
        let vault = try makeVault(staking: [TokensStore.ruji])
        let keychain = MockKeychainService(lastMigratedVersion: PromoBannerDismissalMigration().version)

        AppMigrationService(keychainService: keychain).performMigrationsIfNeeded()

        XCTAssertEqual(stakingTickers(vault), ["RUJI", "SRUJI"])
        XCTAssertEqual(
            keychain.lastMigratedVersion,
            RujiAutoCompoundPositionMigration().version,
            "the migration version must ratchet forward so it does not re-run"
        )
    }

    /// Already migrated ⇒ nothing runs, which is what stops a deliberate opt-out
    /// being undone on every launch.
    func testDoesNotRunAgainOnceTheVersionHasRatchetedForward() throws {
        let vault = try makeVault(staking: [TokensStore.ruji])
        let keychain = MockKeychainService(lastMigratedVersion: RujiAutoCompoundPositionMigration().version)

        AppMigrationService(keychainService: keychain).performMigrationsIfNeeded()

        XCTAssertEqual(stakingTickers(vault), ["RUJI"])
    }

    /// End to end: a vault that was auto-compounding under the old single-card
    /// model gets its compounded card back from the very next refresh, without
    /// the migration writing anything into `vault.coins` — THORChain discovery
    /// has already added the receipt for any vault that holds one.
    func testMigratedVaultThatHoldsTheReceiptEmitsTheCompoundedCard() async throws {
        let vault = try makeVault(staking: [TokensStore.ruji])
        let address = "thor1fixturevaultaddress00000000000000000000"
        let hexPublicKey = "02" + String(repeating: "00", count: 32)
        vault.coins.append(Coin(asset: TokensStore.rune, address: address, hexPublicKey: hexPublicKey))
        vault.coins.append(Coin(asset: TokensStore.ruji, address: address, hexPublicKey: hexPublicKey))
        // Added by THORChain token discovery because the vault holds the receipt.
        vault.coins.append(Coin(asset: TokensStore.sruji, address: address, hexPublicKey: hexPublicKey))
        try Storage.shared.save()

        try RujiAutoCompoundPositionMigration().migrate()

        let details = StakingDetails(
            stakedAmount: 0,
            autoCompoundAmount: Decimal(string: "14064.86651509")!,
            apr: nil,
            estimatedReward: nil,
            nextPayoutDate: nil,
            rewards: nil,
            rewardsCoin: nil
        )
        let dtos = await THORChainStakeInteractor(stakingService: MockTHORChainStakingService(details: details))
            .fetchStakePositions(vault: vault)

        let compounded = try XCTUnwrap(dtos.first { $0.coin.ticker.uppercased() == "SRUJI" })
        XCTAssertEqual(compounded.amount, Decimal(string: "14064.86651509"))
        XCTAssertEqual(compounded.type, .compound)
    }

    /// Newer than every shipped migration, so registering it does not replay them.
    func testVersionIsAheadOfTheShippedMigrations() {
        XCTAssertEqual(RujiAutoCompoundPositionMigration().version, 3)
        XCTAssertGreaterThan(
            RujiAutoCompoundPositionMigration().version,
            PromoBannerDismissalMigration().version
        )
        XCTAssertGreaterThan(
            RujiAutoCompoundPositionMigration().version,
            TonGramRebrandMigration().version
        )
        XCTAssertGreaterThan(
            RujiAutoCompoundPositionMigration().version,
            THORChainDuplicateTokensMigration().version
        )
    }
}
