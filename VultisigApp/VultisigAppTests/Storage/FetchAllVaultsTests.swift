//
//  FetchAllVaultsTests.swift
//  VultisigAppTests
//
//  Cover for replacing the two root-level `@Query var vaults: [Vault]`
//  declarations with `ModelContext.fetchAllVaults()`.
//
//  This is a refactor, so the burden is showing nothing changed. What could
//  drift is the *list a reader is handed*: a fetch that sorted differently,
//  dropped rows, or threw where the query returned empty would change which
//  vault the app selects at launch and which vaults the notification prompt
//  marks. Each of those is pinned below.
//

import SwiftData
import SwiftUI
import XCTest
@testable import VultisigApp

@MainActor
final class FetchAllVaultsTests: XCTestCase {

    private var token: TestContextToken!
    private var context: ModelContext!
    /// `AppViewModel` remembers the selected vault in `@AppStorage`, which is the
    /// standard defaults suite whichever container the store is on.
    private var borrowedDefaults: [String: Any?] = [:]
    private let borrowedDefaultsKeys = ["vaultName", "selectedPubKeyECDSA"]

    override func setUpWithError() throws {
        try super.setUpWithError()
        token = try TestStore.installInMemoryContainer()
        context = token.container.mainContext
        // `AppViewModel.set(selectedVault:)` starts an unstructured eligibility
        // refresh that resumes after this test returns. `insertVaults` stamps the
        // fixtures fresh so that task returns at its first line and never writes
        // or saves — this keeps the container alive for the read it still does on
        // the way there, which would otherwise trap in whichever test is running
        // by then.
        TestStore.retain(token.container)

        for key in borrowedDefaultsKeys {
            borrowedDefaults[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for (key, value) in borrowedDefaults {
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        borrowedDefaults = [:]
        TestStore.restore(token)
        token = nil
        context = nil
        super.tearDown()
    }

    // MARK: - The fetch itself

    func testFetchAllVaultsReturnsEveryStoredVault() throws {
        let inserted = try insertVaults(3)

        let fetched = context.fetchAllVaults()

        XCTAssertEqual(fetched.count, inserted.count)
        XCTAssertEqual(
            Set(fetched.map(\.pubKeyECDSA)),
            Set(inserted.map(\.pubKeyECDSA))
        )
    }

    func testFetchVaultsIfAvailableAnswersWithTheListWhenTheStoreIsReadable() throws {
        try insertVaults(2)

        let fetched = try XCTUnwrap(
            context.fetchVaultsIfAvailable(),
            "a readable store must answer with a list, never nil"
        )
        XCTAssertEqual(fetched.count, 2)
    }

    /// An empty store is readable, so it answers with an empty list — not `nil`.
    /// `nil` is reserved for "could not read", which is what keeps the launch
    /// auth gate from treating an unreadable store as a vault-less one.
    func testFetchVaultsIfAvailableDistinguishesEmptyFromUnreadable() {
        XCTAssertEqual(context.fetchVaultsIfAvailable()?.count, 0)
    }

    /// The ordering pin. An unsorted `@Query var vaults: [Vault]` and an unsorted
    /// `FetchDescriptor<Vault>` both take the store's own order, and the helper
    /// must not quietly introduce one of its own — `loadSelectedVault(for:)`
    /// falls back to `vaults.first`, so a sort here silently changes which vault
    /// a fresh install opens on.
    func testFetchAllVaultsMatchesAnUnsortedFetchDescriptor() throws {
        try insertVaults(4)

        let helper = context.fetchAllVaults()
        let descriptor = try context.fetch(FetchDescriptor<Vault>())

        XCTAssertEqual(helper.count, 4, "fixtures must not have collapsed on a unique attribute")
        XCTAssertEqual(helper.count, descriptor.count)
        for (fromHelper, fromDescriptor) in zip(helper, descriptor) {
            XCTAssertTrue(fromHelper === fromDescriptor)
        }
    }

    func testFetchAllVaultsIsEmptyWithNothingStored() {
        XCTAssertTrue(context.fetchAllVaults().isEmpty)
    }

    func testFetchAllVaultsSeesAVaultInsertedAfterAnEarlierFetch() throws {
        XCTAssertTrue(context.fetchAllVaults().isEmpty)

        try insertVaults(1)

        XCTAssertEqual(context.fetchAllVaults().map(\.pubKeyECDSA), ["ecdsa-0"])
    }

    // MARK: - Selected-vault resolution

    func testLoadSelectedVaultPicksTheFirstFetchedVaultWhenNoneRemembered() throws {
        try insertVaults(3)

        let fetched = context.fetchAllVaults()
        let viewModel = makeAppViewModel()

        viewModel.loadSelectedVault(for: fetched)

        XCTAssertTrue(viewModel.selectedVault === fetched.first)
        XCTAssertTrue(viewModel.showingVaultSelector)
    }

    func testLoadSelectedVaultResolvesTheRememberedVault() throws {
        try insertVaults(3)

        let fetched = context.fetchAllVaults()
        let remembered = try XCTUnwrap(fetched.last)
        let viewModel = makeAppViewModel()
        viewModel.vaultName = remembered.name
        viewModel.selectedPubKeyECDSA = remembered.pubKeyECDSA

        viewModel.loadSelectedVault(for: fetched)

        XCTAssertTrue(viewModel.selectedVault === remembered)
        XCTAssertFalse(viewModel.showingVaultSelector)
    }

    func testLoadSelectedVaultClearsSelectionWhenTheRememberedVaultIsGone() throws {
        try insertVaults(1)

        let viewModel = makeAppViewModel()
        viewModel.vaultName = "A vault that was deleted"
        viewModel.selectedPubKeyECDSA = "gone"

        viewModel.loadSelectedVault(for: context.fetchAllVaults())

        XCTAssertNil(viewModel.selectedVault)
        XCTAssertTrue(viewModel.showingVaultSelector)
    }

    // MARK: - The push-notification setup path

    /// `SetupPushNotificationsModifier`'s first-run case marks **every** vault as
    /// prompted, so the intro sheet is spent once for the whole install rather
    /// than once per vault. What the query-to-fetch swap could break there is the
    /// list: an incomplete one leaves some vaults unmarked and re-prompts them.
    ///
    /// **Scope, stated rather than implied.** This drives the fetch and the
    /// marking, which is what changed. It does **not** invoke `checkIfNeeded()`
    /// — that method is `private` on a `ViewModifier` whose memberwise
    /// initializer is private too, so its case-1/case-2 selection and its
    /// empty-list fall-through are not reachable from a test without extracting
    /// the decision into a value type. Worth doing; deliberately not done in a
    /// change whose point is to remove a property wrapper.
    func testEveryFetchedVaultCanBeMarkedPrompted() throws {
        try insertVaults(3)

        let manager = PushNotificationManager()
        let vaults = context.fetchAllVaults()
        XCTAssertEqual(vaults.count, 3)
        XCTAssertTrue(vaults.allSatisfy { !manager.hasPromptedVaultNotification($0) })

        for vault in vaults {
            manager.markVaultNotificationPrompted(vault)
        }

        let after = context.fetchAllVaults()
        XCTAssertEqual(after.count, 3)
        XCTAssertTrue(after.allSatisfy { manager.hasPromptedVaultNotification($0) })
    }

    // MARK: - The amplifier, pinned structurally

    /// The point of the change: the app's root view declares no SwiftData
    /// `@Query`, so a `@Model` write anywhere in the app cannot re-evaluate the
    /// whole view tree through it.
    ///
    /// Structural rather than behavioural, and deliberately so — counting body
    /// evaluations under a store write needs a real `NSWindow`/`NSHostingView`
    /// host driving a render loop, which does not exist in a unit-test bundle and
    /// is not worth building in one. What this can prove is the property the
    /// measurement was about: the declaration is not there. Re-adding one fails
    /// here, which is the regression that matters.
    func testRootViewDeclaresNoLiveQuery() {
        let root = ContentView(navigationRouter: NavigationRouter())

        XCTAssertEqual(
            queryProperties(of: root),
            [],
            "ContentView is the root of the whole NavigationStack — a @Query here re-evaluates every screen in the app on any store change"
        )
    }

    /// The same, for the second declaration: this modifier is applied to the home
    /// screen, so a `@Query` on it puts the amplifier back on the home tree even
    /// with `ContentView` clean.
    func testPushNotificationsModifierDeclaresNoLiveQuery() throws {
        let vault = try XCTUnwrap(insertVaults(1).first)
        // Through the public entry point, because the modifier's memberwise
        // initializer is private (it has private `@State`). `ModifiedContent`
        // stores the modifier, so reflection reaches it from the wrapped view.
        let modified = EmptyView().withSetupPushNotifications(vault: vault)

        let modifier = try XCTUnwrap(
            Mirror(reflecting: modified).children.first { $0.label == "modifier" }?.value,
            "ModifiedContent should store the modifier this reflects on"
        )
        XCTAssertTrue(modifier is SetupPushNotificationsModifier)

        XCTAssertEqual(
            queryProperties(of: modifier),
            [],
            "SetupPushNotificationsModifier is applied to HomeScreen — a @Query here reinstates the whole-window invalidation on the home tree"
        )
    }

    // MARK: - Helpers

    private func makeAppViewModel() -> AppViewModel {
        AppViewModel(reconcileInstall: { .nothing })
    }

    /// Inserts `count` distinct vaults and returns them in insertion order.
    ///
    /// Not `TestStore.makeVault(pubKey:)`: that fixture varies `pubKeyECDSA` but
    /// hard-codes `pubKeyEdDSA`, and all three of `name` / `pubKeyECDSA` /
    /// `pubKeyEdDSA` are `@Attribute(.unique)`. SwiftData answers a duplicate
    /// unique value with an **upsert**, not an error, so N fixtures sharing one
    /// collapse into a single row — silently, and a count assertion is the only
    /// thing that notices.
    @discardableResult
    private func insertVaults(_ count: Int) throws -> [Vault] {
        let vaults = (0..<count).map { index -> Vault in
            let vault = Vault(
                name: "Vault \(index)",
                signers: [],
                pubKeyECDSA: "ecdsa-\(index)",
                pubKeyEdDSA: "eddsa-\(index)",
                keyshares: [],
                localPartyID: "party-\(index)",
                hexChainCode: "hex",
                resharePrefix: nil,
                libType: .DKLS
            )
            // `AppViewModel.set(selectedVault:)` fires an unstructured
            // `refreshIfStale`. A fresh stamp makes it return at its first line,
            // so it never reaches the write or the `Storage.shared.save()` that
            // would otherwise land in whichever context this test's teardown
            // restored.
            vault.fastVaultEligibilityCheckedAt = Date()
            context.insert(vault)
            return vault
        }
        try Storage.shared.save()
        return vaults
    }

    /// The labels of `subject`'s stored properties that are SwiftData `@Query`
    /// wrappers. Reflection because a property wrapper leaves no other trace a
    /// test can assert on.
    private func queryProperties(of subject: Any) -> [String] {
        Mirror(reflecting: subject).children.compactMap { child in
            let type = String(describing: type(of: child.value))
            guard type.hasPrefix("Query<") || type.contains(".Query<") else { return nil }
            return child.label ?? "<unlabelled>"
        }
    }
}
