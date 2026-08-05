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

    // MARK: - A chain that could not be built

    /// The half the first fix was blind to. `CoinFactory.create` throwing for
    /// one chain used to leave that chain out of the list the postcondition was
    /// then checked against — so a vault missing a chain reported itself fully
    /// prepared, which is the symptom that was reported in the first place.
    ///
    /// One corrupt per-chain key is the narrowest way to say it: Bitcoin still
    /// builds, Tron cannot, and what must not happen is a vault stored holding
    /// only Bitcoin and called done.
    func testAChainThatCouldNotBeBuiltIsReportedAsUnprepared() throws {
        let vault = vaultWithOneChainItCannotBuild()
        context.insert(vault)
        try context.save()

        XCTAssertFalse(makeService().setDefaultCoinsOnce(vault: vault), "a chain that could not be built is a chain the user will not have")
        try context.save()

        XCTAssertEqual(
            try storedChains(), [.bitcoin],
            "the chain that could be built is kept — keygen ignores this answer, so undoing would cost it every chain it can derive"
        )
    }

    /// The `coins.isEmpty` short-circuit used to answer `true` for a vault
    /// holding any coin at all. That is what made the import's retry
    /// meaningless: the first pass comes up a chain short, the second sees
    /// coins on the vault and blesses it as prepared, and the reporting the
    /// whole postcondition exists for reports nothing.
    func testAVaultStillMissingAChainIsNotBlessedOnASecondRun() throws {
        let vault = vaultWithOneChainItCannotBuild()
        context.insert(vault)
        try context.save()
        XCTAssertFalse(makeService().setDefaultCoinsOnce(vault: vault))
        try context.save()

        XCTAssertFalse(makeService().setDefaultCoinsOnce(vault: vault), "still missing Tron, so still unprepared")
        XCTAssertEqual(try storedChains(), [.bitcoin], "and a second run must not write a second Bitcoin beside the first")
    }

    /// The expectation is the chains the vault was asked for, so a default
    /// chain the catalog carries no native asset for could never be satisfied.
    /// Nothing else in the app states that correspondence, and the catalog is
    /// edited far more often than this file is.
    func testEveryBaseDefaultChainHasANativeAssetToBuild() {
        let natives = Set(TokensStore.TokenSelectionAssets.filter(\.isNativeToken).map(\.chain))
        for chain in makeService().baseDefaultChains {
            XCTAssertTrue(natives.contains(chain), "\(chain.name) is a default chain with no native asset in the catalog")
        }
    }

    /// And the degenerate case the same `allSatisfy` answered `true` for:
    /// nothing built at all. An empty list satisfies every postcondition, so the
    /// check passed at exactly the moment there was nothing to check.
    func testAVaultNothingCouldBeBuiltForIsReportedAsUnprepared() throws {
        let vault = Vault(
            name: "Unusable keys",
            signers: [],
            pubKeyECDSA: "not-a-public-key",
            pubKeyEdDSA: "not-a-public-key-either",
            keyshares: [],
            localPartyID: "party",
            hexChainCode: "not-a-chain-code",
            resharePrefix: nil,
            libType: .DKLS
        )
        context.insert(vault)
        try context.save()

        XCTAssertFalse(makeService().setDefaultCoinsOnce(vault: vault), "no chains at all is the failure being reported, not a vacuous success")
        XCTAssertTrue(vault.coins.isEmpty)
    }

    // MARK: - When token discovery is allowed to run

    /// The point of the split. Discovery is network work that outlives the call
    /// and writes on its own; started while the vault is only *attached* it can
    /// come back and persist one whose save failed. So the pass records, the
    /// caller starts — and only once its save has landed.
    func testDiscoveryRunsForEveryCoinThePassAttached() async throws {
        let recorder = DiscoveryRecorder()
        let service = makeService(discoveringWith: recorder)
        let vault = TestStore.makeDerivableVault(keyshare: share)
        context.insert(vault)
        try context.save()

        XCTAssertTrue(service.setDefaultCoinsOnce(vault: vault))
        try context.save()
        await service.startTokenDiscovery().value

        XCTAssertEqual(Set(recorder.chains), Set(TestStore.derivableChains))
    }

    /// Started twice, it does not do the same round trip twice.
    func testDiscoveryIsNotStartedAgainForCoinsItAlreadyCovered() async throws {
        let recorder = DiscoveryRecorder()
        let service = makeService(discoveringWith: recorder)
        let vault = TestStore.makeDerivableVault(keyshare: share)
        context.insert(vault)
        try context.save()
        service.setDefaultCoinsOnce(vault: vault)
        try context.save()

        await service.startTokenDiscovery().value
        await service.startTokenDiscovery().value

        XCTAssertEqual(recorder.chains.count, TestStore.derivableChains.count)
    }

    /// The withdrawal case, which is what a failed preparation save leaves
    /// behind: the coins were attached, the save did not take, and the context
    /// took them back. Discovery must not write against them — writing is what
    /// would persist a vault the import gave up on.
    func testDiscoveryDoesNotRunForCoinsAFailedSaveTookBack() async throws {
        let recorder = DiscoveryRecorder()
        let service = makeService(discoveringWith: recorder)
        let vault = TestStore.makeDerivableVault(keyshare: share)
        context.insert(vault)
        try context.save()
        service.setDefaultCoinsOnce(vault: vault)

        context.rollback()
        await service.startTokenDiscovery().value

        XCTAssertTrue(recorder.chains.isEmpty, "the coins are not stored, so there is nothing to discover against")
    }

    /// And the case that traps rather than merely writing: the vault is gone by
    /// the time discovery gets to run. Nothing live is carried across that gap,
    /// so what is left is a lookup that finds nothing.
    func testDiscoveryDoesNotRunForAVaultThatIsNoLongerStored() async throws {
        let recorder = DiscoveryRecorder()
        let service = makeService(discoveringWith: recorder)
        let vault = TestStore.makeDerivableVault(keyshare: share)
        context.insert(vault)
        try context.save()
        service.setDefaultCoinsOnce(vault: vault)
        try context.save()

        context.delete(vault)
        try context.save()
        await service.startTokenDiscovery().value

        XCTAssertTrue(recorder.chains.isEmpty, "a deleted vault must not be written back to")
    }

    // MARK: - Helpers

    private func makeService() -> VaultDefaultCoinService {
        VaultDefaultCoinService(context: context)
    }

    /// Bitcoin builds from a usable per-chain key; Tron cannot build at all.
    /// Both resolve to `NoTokenDiscoverer`, so the fixture stays hermetic.
    private func vaultWithOneChainItCannotBuild() -> Vault {
        let vault = TestStore.makeDerivableVault(keyshare: share)
        let usable = vault.chainPublicKeys.first?.publicKeyHex ?? ""
        vault.chainPublicKeys = [
            ChainPublicKey(chain: .bitcoin, publicKeyHex: usable, isEddsa: false),
            ChainPublicKey(chain: .tron, publicKeyHex: "not-a-public-key", isEddsa: false)
        ]
        return vault
    }

    private func makeService(discoveringWith recorder: DiscoveryRecorder) -> VaultDefaultCoinService {
        VaultDefaultCoinService(context: context) { coin, vault in
            recorder.record(coin, vault)
        }
    }

    /// Read back through a context that never saw the in-memory objects, so an
    /// unsaved relationship cannot answer for a saved one.
    private func storedChains() throws -> [Chain] {
        try ModelContext(token.container).fetch(FetchDescriptor<Vault>()).flatMap(\.coins).map(\.chain)
    }
}

/// Stands in for the discovery that in production goes to the network and
/// writes what it finds, so the tests can assert on *whether* it was asked to
/// run rather than on what it found.
@MainActor
private final class DiscoveryRecorder {
    private(set) var calls: [(chain: Chain, vaultName: String)] = []

    var chains: [Chain] { calls.map(\.chain) }

    func record(_ coin: Coin, _ vault: Vault) {
        calls.append((coin.chain, vault.name))
    }
}
