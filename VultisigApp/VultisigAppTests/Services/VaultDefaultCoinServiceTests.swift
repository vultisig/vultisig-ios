//
//  VaultDefaultCoinServiceTests.swift
//  VultisigAppTests
//

import SwiftData
import XCTest
@testable import VultisigApp

/// The service has two callers, and they hand it a vault in two different
/// states: keygen prepares one that has never been inserted, the backup import
/// prepares one that has already been inserted *and saved*. Those are not the
/// same thing to SwiftData, and the difference is where a real regression lived
/// — attaching a coin by appending to `vault.coins` does not register on a vault
/// that has been through a `save()`, so an import wrote its coin rows belonging
/// to nobody and the wallet came up with no chains in it and no error anywhere.
///
/// So both orders are pinned here, not just the one a given caller uses today.
@MainActor
final class VaultDefaultCoinServiceTests: XCTestCase {

    private var token: TestContextToken!
    private var context: ModelContext!

    private let share = "eyJrZXlzaGFyZSI6ImRrbHMifQ=="

    override func setUpWithError() throws {
        try super.setUpWithError()
        token = try TestStore.installInMemoryContainer()
        context = token.container.mainContext
        // `setDefaultCoins` starts a token-discovery `Task` per coin that
        // outlives the test method and touches the models it captured.
        TestStore.retain(token.container)
    }

    override func tearDown() {
        context = nil
        TestStore.restore(token)
        token = nil
        super.tearDown()
    }

    // MARK: - Both orders

    /// Keygen's order: the vault is prepared before it ever reaches the context.
    func testAVaultThatHasNotBeenInsertedGetsItsDefaultCoins() throws {
        let vault = TestStore.makeDerivableVault(keyshare: share)

        XCTAssertTrue(makeService().setDefaultCoinsOnce(vault: vault))

        context.insert(vault)
        try context.save()
        XCTAssertEqual(Set(try storedChains()), Set(TestStore.derivableChains))
    }

    /// The import's order: the vault is already on disk when it is prepared.
    /// This is the one that broke.
    func testAVaultThatHasAlreadyBeenSavedGetsItsDefaultCoins() throws {
        let vault = TestStore.makeDerivableVault(keyshare: share)
        context.insert(vault)
        try context.save()

        XCTAssertTrue(makeService().setDefaultCoinsOnce(vault: vault))
        try context.save()

        XCTAssertEqual(Set(try storedChains()), Set(TestStore.derivableChains))
    }

    /// The half that made the failure silent rather than merely wrong: the coin
    /// rows were written either way, so counting them proved nothing. What was
    /// lost was which vault they belonged to.
    func testNoCoinIsLeftWithNoVaultToBelongTo() throws {
        let vault = TestStore.makeDerivableVault(keyshare: share)
        context.insert(vault)
        try context.save()

        makeService().setDefaultCoinsOnce(vault: vault)
        try context.save()

        let fresh = ModelContext(token.container)
        let coins = try fresh.fetch(FetchDescriptor<Coin>())
        XCTAssertFalse(coins.isEmpty)
        XCTAssertTrue(coins.allSatisfy { $0.vault != nil })
    }

    /// The DeFi chains are derived in the same pass and have to survive it too.
    func testTheDefiChainsDerivedAlongsideTheCoinsPersist() throws {
        let vault = TestStore.makeDerivableVault(keyshare: share)
        context.insert(vault)
        try context.save()

        makeService().setDefaultCoinsOnce(vault: vault)
        try context.save()

        let fresh = ModelContext(token.container)
        let stored = try XCTUnwrap(try fresh.fetch(FetchDescriptor<Vault>()).first)
        XCTAssertTrue(stored.defiChains.contains(.tron))
    }

    // MARK: - What "prepared" means

    /// Re-runnable by design, and the import relies on that to retry: a vault
    /// that already has coins is left exactly as it is.
    func testAVaultThatAlreadyHasCoinsIsLeftAlone() throws {
        let vault = TestStore.makeDerivableVault(keyshare: share)
        context.insert(vault)
        try context.save()
        makeService().setDefaultCoinsOnce(vault: vault)
        try context.save()
        let after = try storedChains().count

        XCTAssertTrue(makeService().setDefaultCoinsOnce(vault: vault))
        try context.save()

        XCTAssertEqual(try storedChains().count, after, "a second run must not duplicate what the first one wrote")
    }

    /// A legacy key-import vault predates `chainPublicKeys`, so there is nothing
    /// to derive for it. Nothing to derive is not a failure to derive — reading
    /// it as one would report every such import as broken.
    func testAVaultWithNothingToDeriveIsNotReportedAsUnprepared() throws {
        let vault = Vault(name: "Legacy KeyImport", libType: .KeyImport)
        vault.chainPublicKeys = []
        context.insert(vault)
        try context.save()

        XCTAssertTrue(makeService().setDefaultCoinsOnce(vault: vault))
        XCTAssertTrue(vault.coins.isEmpty)
    }

    // MARK: - Helpers

    private func makeService() -> VaultDefaultCoinService {
        VaultDefaultCoinService(context: context)
    }

    /// Read back through a context that never saw the in-memory objects, so an
    /// unsaved relationship cannot answer for a saved one.
    private func storedChains() throws -> [Chain] {
        try ModelContext(token.container).fetch(FetchDescriptor<Vault>()).flatMap(\.coins).map(\.chain)
    }
}
