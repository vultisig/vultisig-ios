//
//  KaminoPositionStorageServiceTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import BigInt
import SwiftData
import XCTest

/// The persisted Earn position doubles as the user's per-vault opt-in, so these
/// pin both halves: that the flag survives a refresh, and that a refresh can
/// never create the flag.
@MainActor
final class KaminoPositionStorageServiceTests: XCTestCase {
    private var storeToken: TestContextToken!
    private var vault: Vault!
    private let storage = KaminoPositionStorageService()

    private let steakhouse = KaminoVaultRegistry.steakhouseUSDC
    private let allez = KaminoVaultRegistry.allezSOL

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

    func testEnablingAVaultCreatesAZeroRowAtTheVaultsPinnedScales() throws {
        try storage.setEnabled(true, descriptor: allez, for: vault)

        let position = try XCTUnwrap(storage.position(for: vault, vaultAddress: allez.address))
        XCTAssertTrue(position.isEnabled)
        XCTAssertEqual(position.tokenAmountDecimal, .zero)
        // The one vault whose scales differ — nothing may assume they match.
        XCTAssertEqual(position.tokenDecimals, 9)
        XCTAssertEqual(position.shareDecimals, 6)
        XCTAssertEqual(vault.kaminoPositions.count, 1)
    }

    /// `KaminoPosition.id` is `@Attribute(.unique)`, so two rows built with the
    /// same `(vaultAddress, pubKeyECDSA)` would silently collapse into one. Two
    /// distinct vaults must therefore stay two rows.
    func testTwoEnabledVaultsPersistAsTwoDistinctRows() throws {
        try storage.setEnabled(true, descriptor: steakhouse, for: vault)
        try storage.setEnabled(true, descriptor: allez, for: vault)

        XCTAssertEqual(vault.kaminoPositions.count, 2)
        XCTAssertEqual(
            Set(vault.kaminoPositions.map(\.id)).count,
            2,
            "Distinct vaults must produce distinct ids or the unique attribute upserts them together."
        )
        XCTAssertEqual(storage.enabledVaultAddresses(for: vault), [steakhouse.address, allez.address])
    }

    func testTheSameVaultUnderTwoVaultKeysStaysTwoRows() throws {
        let other = makeSecondVault()

        try storage.setEnabled(true, descriptor: steakhouse, for: vault)
        try storage.setEnabled(true, descriptor: steakhouse, for: other)

        XCTAssertEqual(vault.kaminoPositions.count, 1)
        XCTAssertEqual(other.kaminoPositions.count, 1)
        XCTAssertNotEqual(vault.kaminoPositions[0].id, other.kaminoPositions[0].id)
    }

    /// Disabling is a display toggle: it does not withdraw, so the snapshot has
    /// to survive for the DeFi total to be right again the moment it is re-enabled.
    func testDisablingKeepsTheRowAndItsSnapshot() throws {
        try storage.setEnabled(true, descriptor: steakhouse, for: vault)
        try storage.upsert(snapshots: [snapshot(for: steakhouse, shares: 500, tokens: 512)], for: vault)

        try storage.setEnabled(false, descriptor: steakhouse, for: vault)

        let position = try XCTUnwrap(storage.position(for: vault, vaultAddress: steakhouse.address))
        XCTAssertFalse(position.isEnabled)
        XCTAssertEqual(position.tokenAmountDecimal, Decimal(string: "0.000512"))
        XCTAssertTrue(storage.enabledVaultAddresses(for: vault).isEmpty)
    }

    func testUpsertPreservesTheOptInFlag() throws {
        try storage.setEnabled(true, descriptor: steakhouse, for: vault)

        try storage.upsert(snapshots: [snapshot(for: steakhouse, shares: 1_000_000, tokens: 1_100_000)], for: vault)

        let position = try XCTUnwrap(storage.position(for: vault, vaultAddress: steakhouse.address))
        XCTAssertTrue(position.isEnabled, "A refresh reports what the vault holds, never whether the user wants to see it.")
        XCTAssertEqual(position.tokenAmountDecimal, Decimal(string: "1.1"))
        XCTAssertEqual(position.shares?.baseUnits, BigInt(1_000_000))
    }

    /// A snapshot for a vault the user never enabled must not conjure a row —
    /// that row IS the opt-in, and its balance would join the DeFi total.
    func testUpsertNeverCreatesARowForAnUnselectedVault() throws {
        try storage.upsert(snapshots: [snapshot(for: allez, shares: 1_000, tokens: 1_000)], for: vault)

        XCTAssertTrue(vault.kaminoPositions.isEmpty)
        XCTAssertNil(storage.position(for: vault, vaultAddress: allez.address))
    }

    /// The registry is the app's record of which vaults exist. A row for a vault
    /// that has left it is not something to render or to count.
    func testAnUncuratedRowIsNotReportedAsEnabled() throws {
        let stray = KaminoPosition(
            vaultAddress: "NotAVaultTheAppKnowsAbout1111111111111111111",
            isEnabled: true,
            shares: KaminoShareAmount(baseUnits: 10, decimals: 6),
            tokenAmount: KaminoTokenAmount(baseUnits: 10, decimals: 6),
            vault: vault
        )
        Storage.shared.insert(stray)
        try Storage.shared.save()

        XCTAssertTrue(storage.enabledVaultAddresses(for: vault).isEmpty)
    }

    // MARK: - Backup carrier

    /// A backup encodes a vault's plain properties, not its position cache, so
    /// the enabled set has to travel as its own field or a restored vault loses
    /// the user's Earn selection.
    func testTheEnabledSelectionSurvivesABackupRoundTrip() throws {
        try storage.setEnabledVaults([steakhouse.address, allez.address], for: vault)

        let encoded = try JSONEncoder().encode(vault)
        let restored = try JSONDecoder().decode(Vault.self, from: encoded)

        XCTAssertEqual(restored.enabledKaminoVaults, [steakhouse.address, allez.address])
        XCTAssertTrue(restored.kaminoPositions.isEmpty, "A backup carries the choice, not the cache.")
    }

    /// A backup written before this field existed must still decode.
    func testALegacyBackupWithoutTheFieldDecodesToAnEmptySelection() throws {
        let encoded = try JSONEncoder().encode(vault)
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        json.removeValue(forKey: "enabledKaminoVaults")
        let legacy = try JSONSerialization.data(withJSONObject: json)

        let restored = try JSONDecoder().decode(Vault.self, from: legacy)

        XCTAssertTrue(restored.enabledKaminoVaults.isEmpty)
    }

    func testHydrationMaterialisesAnImportedSelectionIntoRows() throws {
        vault.enabledKaminoVaults = [steakhouse.address, allez.address]

        try storage.hydrateEnabledVaultsIfNeeded(for: vault)

        XCTAssertEqual(vault.kaminoPositions.count, 2)
        XCTAssertEqual(storage.enabledVaultAddresses(for: vault), [steakhouse.address, allez.address])
        XCTAssertEqual(
            storage.position(for: vault, vaultAddress: allez.address)?.tokenDecimals,
            9,
            "A hydrated row must carry the vault's pinned scales, not a default."
        )
    }

    func testHydrationIsIdempotentAndNeverDisables() throws {
        vault.enabledKaminoVaults = [steakhouse.address]
        try storage.hydrateEnabledVaultsIfNeeded(for: vault)
        try storage.upsert(snapshots: [snapshot(for: steakhouse, shares: 500, tokens: 512)], for: vault)

        try storage.hydrateEnabledVaultsIfNeeded(for: vault)
        try storage.hydrateEnabledVaultsIfNeeded(for: vault)

        XCTAssertEqual(vault.kaminoPositions.count, 1, "Repeated hydration must not duplicate a row.")
        XCTAssertEqual(
            storage.position(for: vault, vaultAddress: steakhouse.address)?.tokenAmountDecimal,
            Decimal(string: "0.000512"),
            "Hydration is additive — it must never overwrite a live snapshot."
        )
    }

    func testHydrationIgnoresAnUncuratedAddress() throws {
        vault.enabledKaminoVaults = ["NotAVaultTheAppKnowsAbout1111111111111111111"]

        try storage.hydrateEnabledVaultsIfNeeded(for: vault)

        XCTAssertTrue(vault.kaminoPositions.isEmpty)
    }

    /// The picker applies the whole selection at once, so a half-applied state
    /// is not representable.
    func testSettingTheWholeSelectionMovesEveryRowAndTheMirrorTogether() throws {
        try storage.setEnabledVaults([steakhouse.address, allez.address], for: vault)
        XCTAssertEqual(vault.enabledKaminoVaults, [steakhouse.address, allez.address])

        try storage.setEnabledVaults([allez.address], for: vault)

        XCTAssertEqual(vault.enabledKaminoVaults, [allez.address])
        XCTAssertFalse(try XCTUnwrap(storage.position(for: vault, vaultAddress: steakhouse.address)).isEnabled)
        XCTAssertTrue(try XCTUnwrap(storage.position(for: vault, vaultAddress: allez.address)).isEnabled)
        XCTAssertEqual(vault.kaminoPositions.count, 2, "The disabled vault keeps its row and snapshot.")
    }

    func testAnUncuratedAddressCanNeverBeTurnedOn() throws {
        try storage.setEnabledVaults(["NotAVaultTheAppKnowsAbout1111111111111111111"], for: vault)

        XCTAssertTrue(vault.kaminoPositions.isEmpty)
        XCTAssertTrue(vault.enabledKaminoVaults.isEmpty)
    }

    /// A second vault distinct in EVERY unique attribute. `TestStore.makeVault`
    /// varies only `pubKeyECDSA`, so two of its vaults share `pubKeyEdDSA` — and
    /// SwiftData upserts on a unique-attribute collision, which surfaces as a
    /// validation failure on the next save rather than as a duplicate row.
    private func makeSecondVault() -> Vault {
        let vault = Vault(
            name: "Second Test Vault",
            signers: [],
            pubKeyECDSA: "second-pub-ecdsa",
            pubKeyEdDSA: "second-pub-eddsa",
            keyshares: [],
            localPartyID: "party-2",
            hexChainCode: "hex-2",
            resharePrefix: nil,
            libType: .DKLS
        )
        Storage.shared.insert(vault)
        return vault
    }

    private func snapshot(
        for descriptor: KaminoVaultDescriptor,
        shares: Int,
        tokens: Int
    ) -> KaminoPositionSnapshot {
        KaminoPositionSnapshot(
            vaultAddress: descriptor.address,
            shares: KaminoShareAmount(baseUnits: BigInt(shares), decimals: descriptor.sharesDecimals),
            tokenAmount: KaminoTokenAmount(baseUnits: BigInt(tokens), decimals: descriptor.tokenDecimals),
            apy30d: Decimal(string: "0.0391"),
            pnlToken: Decimal(string: "1.25")
        )
    }
}
