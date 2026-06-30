//
//  VaultDetailViewModelTests.swift
//  VultisigAppTests
//
//  Regression tests for the membership-aware seed guard in
//  `VaultDetailViewModel.updateBalance(vault:)`:
//
//      chains.isEmpty
//        || chainsVaultPubKeyECDSA != vault.pubKeyECDSA
//        || Set(vault.chainsWithCoins) != Set(chains)
//
//  The synchronous seed rebuilds both `chains` and the `rows` projection. These
//  tests pin the invariants it must preserve:
//
//    1. First call on an empty model seeds synchronously.
//    2. Switching to a different vault re-seeds synchronously, even with a
//       non-empty `chains` array.
//    3. A same-vault, same-membership refresh does *not* synchronously re-sort
//       (balances changed only) — preserves the fix for the visible
//       "stale-then-fresh" double reorder on post-swap refreshes.
//    4. A same-vault refresh where chain membership changed (a chain was
//       added/removed) DOES re-seed synchronously, so the row appears/leaves
//       in the same runloop as the save — no vault switch required.
//    5. `groupChains(vault:)` keeps the identity tracker in sync so a
//       subsequent same-vault, same-membership `updateBalance` still skips.
//    6. The `chainRows` builder projects the expected rows, and two builds from
//       equal inputs are `==` (Equatable rows).
//

import Foundation
import XCTest
@testable import VultisigApp

@MainActor
final class VaultDetailViewModelTests: XCTestCase {

    func testUpdateBalance_firstCall_seedsChainsSynchronously() {
        let vault = makeVault(pubKey: "vault-a", chains: [.bitcoin, .ethereum])
        let vm = VaultDetailViewModel()

        vm.updateBalance(vault: vault)

        XCTAssertEqual(Set(vm.chains), Set(vault.chainsWithCoins))
        XCTAssertEqual(Set(vm.rows.map(\.chain)), Set(vault.chainsWithCoins))
    }

    /// The bug: switching vaults with a non-empty `chains` array used to skip
    /// the synchronous seed entirely. After this fix the seed fires when the
    /// vault identity flips, so the list reflects the new vault before the
    /// debounced async refresh runs.
    func testUpdateBalance_vaultSwitch_reSeedsChainsSynchronously() {
        let vaultA = makeVault(pubKey: "vault-a", chains: [.bitcoin, .ethereum])
        let vaultB = makeVault(pubKey: "vault-b", chains: [.solana, .gaiaChain])
        let vm = VaultDetailViewModel()

        vm.updateBalance(vault: vaultA)
        XCTAssertEqual(Set(vm.chains), Set(vaultA.chainsWithCoins))

        // Different vault, same VM — `chains` is non-empty but belongs to
        // vault A. The synchronous seed must still fire.
        vm.updateBalance(vault: vaultB)
        XCTAssertEqual(Set(vm.chains), Set(vaultB.chainsWithCoins))
        XCTAssertEqual(Set(vm.rows.map(\.chain)), Set(vaultB.chainsWithCoins))
        XCTAssertFalse(vm.chains.contains(where: { vaultA.chainsWithCoins.contains($0) && !vaultB.chainsWithCoins.contains($0) }),
                       "Stale chains from vault A must not survive the switch to vault B")
    }

    /// A same-vault refresh where chain membership is unchanged (only balances
    /// moved) must NOT synchronously re-sort. The "stale-then-fresh" double
    /// reorder this gate was originally added to prevent depends on this
    /// invariant: with the chain set unchanged, the existing order survives the
    /// synchronous pass and is only refined by the async tail.
    func testUpdateBalance_sameVaultSameMembership_doesNotReSeedChains() {
        let vault = makeVault(pubKey: "vault-a", chains: [.bitcoin, .ethereum])
        let vm = VaultDetailViewModel()

        vm.updateBalance(vault: vault)

        // Same membership, deliberately different order. A synchronous re-seed
        // would re-sort this back to balance/index order and clobber it.
        let reordered = Array(vm.chains.reversed())
        XCTAssertNotEqual(reordered, vm.chains, "precondition: order must actually differ")
        vm.chains = reordered

        vm.updateBalance(vault: vault)

        XCTAssertEqual(vm.chains, reordered,
                       "Same-vault, same-membership updateBalance must not synchronously re-sort chains")
    }

    /// Adding a chain on the SAME vault (no identity flip) must surface
    /// the new chain synchronously via the membership-aware seed — without
    /// waiting on the network-gated async balance tail.
    func testUpdateBalance_sameVault_chainAdded_buildsRowSynchronously() {
        let vault = makeVault(pubKey: "vault-a", chains: [.bitcoin, .ethereum])
        let vm = VaultDetailViewModel()

        vm.updateBalance(vault: vault)
        XCTAssertFalse(vm.rows.contains(where: { $0.chain == .solana }))

        // Add a Solana native coin to the same vault, then refresh.
        appendNativeCoin(to: vault, chain: .solana)
        vm.updateBalance(vault: vault)

        XCTAssertTrue(vm.chains.contains(.solana),
                      "A chain added on the same vault must appear in `chains` synchronously")
        XCTAssertTrue(vm.rows.contains(where: { $0.chain == .solana }),
                      "A chain added on the same vault must appear in `rows` synchronously")
    }

    /// Symmetric removal — dropping a chain's coins on the same vault
    /// must drop its row synchronously.
    func testUpdateBalance_sameVault_chainRemoved_dropsRowSynchronously() {
        let vault = makeVault(pubKey: "vault-a", chains: [.bitcoin, .ethereum, .solana])
        let vm = VaultDetailViewModel()

        vm.updateBalance(vault: vault)
        XCTAssertTrue(vm.rows.contains(where: { $0.chain == .solana }))

        // Remove all Solana coins, then refresh.
        vault.coins.removeAll(where: { $0.chain == .solana })
        vm.updateBalance(vault: vault)

        XCTAssertFalse(vm.chains.contains(.solana),
                       "A chain removed on the same vault must leave `chains` synchronously")
        XCTAssertFalse(vm.rows.contains(where: { $0.chain == .solana }),
                       "A chain removed on the same vault must leave `rows` synchronously")
    }

    /// `groupChains(vault:)` is another seed site. It must update the identity
    /// tracker so a subsequent `updateBalance(vault:)` call against the same
    /// vault (same membership) hits the skip branch (no double seed).
    func testGroupChains_updatesIdentityTracker_soSameVaultUpdateDoesNotReSeed() {
        let vault = makeVault(pubKey: "vault-a", chains: [.bitcoin, .ethereum])
        let vm = VaultDetailViewModel()

        vm.groupChains(vault: vault)

        let reordered = Array(vm.chains.reversed())
        XCTAssertNotEqual(reordered, vm.chains, "precondition: order must actually differ")
        vm.chains = reordered

        vm.updateBalance(vault: vault)

        XCTAssertEqual(vm.chains, reordered,
                       "updateBalance after groupChains for the same vault/membership must not re-seed")
    }

    // MARK: - chainRows builder

    /// The projection builds one row per chain, ordered to match
    /// `sortedChains(vault:)`, with the right asset count per chain.
    func testChainRows_buildsExpectedProjection() {
        let vault = makeVault(pubKey: "vault-a", chains: [.bitcoin, .ethereum])
        // Give Ethereum a second (token) coin so its assetCount is 2.
        appendNativeCoin(to: vault, chain: .ethereum)
        let logic = VaultDetailLogic()

        let rows = logic.chainRows(vault: vault)

        XCTAssertEqual(Set(rows.map(\.chain)), [.bitcoin, .ethereum])
        XCTAssertEqual(rows.map(\.chain), logic.sortedChains(vault: vault),
                       "Row order must match sortedChains(vault:)")
        XCTAssertEqual(rows.first(where: { $0.chain == .ethereum })?.assetCount, 2)
        XCTAssertEqual(rows.first(where: { $0.chain == .bitcoin })?.assetCount, 1)
    }

    /// Equal inputs must produce equal rows (Equatable) so SwiftUI can skip
    /// re-rendering unchanged rows during scroll.
    func testChainRows_equalInputsProduceEqualRows() {
        let vault = makeVault(pubKey: "vault-a", chains: [.bitcoin, .ethereum, .solana])
        let logic = VaultDetailLogic()

        let first = logic.chainRows(vault: vault)
        let second = logic.chainRows(vault: vault)

        XCTAssertEqual(first, second, "Two builds from the same vault must be ==")
    }

    // MARK: - filteredRows search parity

    /// Searching the native asset ticker must surface chains whose `chain.ticker`
    /// differs from the asset — Base/Arbitrum/Optimism hold native ETH but
    /// `chain.ticker` is BASE/ARB/OP. Pre-projection search matched the native
    /// coin's ticker; the projection carries it as `nativeTicker` to keep parity.
    func testFilteredRows_searchByNativeAssetTicker_matchesEthL2Chains() {
        let vault = makeVault(pubKey: "vault-l2", chains: [])
        vault.coins = [
            makeNativeCoin(pubKey: "vault-l2", chain: .base, ticker: "ETH"),
            makeNativeCoin(pubKey: "vault-l2", chain: .bitcoin, ticker: "BTC")
        ]
        let logic = VaultDetailLogic()
        let rows = logic.chainRows(vault: vault)

        XCTAssertEqual(rows.first(where: { $0.chain == .base })?.nativeTicker, "ETH",
                       "Row must carry the native coin ticker (ETH), not chain.ticker (BASE)")

        let ethMatches = logic.filteredRows(searchText: "ETH", rows: rows)
        XCTAssertTrue(ethMatches.contains(where: { $0.chain == .base }),
                      "Searching 'ETH' must surface Base — its native asset is ETH")
        XCTAssertFalse(ethMatches.contains(where: { $0.chain == .bitcoin }),
                       "Bitcoin must not match an 'ETH' search")

        let baseMatches = logic.filteredRows(searchText: "base", rows: rows)
        XCTAssertTrue(baseMatches.contains(where: { $0.chain == .base }),
                      "Chain still resolves by name")
    }

    // MARK: - Promo banner dismissal: global store + per-banner rule

    /// AC: a dismissal made against one vault must not resurface when the user
    /// switches to a different vault. The store is keyed by intent, never by
    /// vault, so this holds structurally.
    func testDismissedBanner_doesNotResurfaceOnVaultSwitch() {
        let store = makeStore()
        let logic = VaultDetailLogic()
        let vaultA = makeVault(pubKey: "vault-a", chains: [.bitcoin])
        let vaultB = makeVault(pubKey: "vault-b", chains: [.solana])

        store.dismiss(.buyVult, now: fixedNow)

        let bannersA = logic.setupBanners(for: vaultA, store: store, now: fixedNow)
        let bannersB = logic.setupBanners(for: vaultB, store: store, now: fixedNow)

        XCTAssertFalse(bannersA.contains(.buyVult))
        XCTAssertFalse(bannersB.contains(.buyVult),
                       "A dismissal must hold across vaults — the store has no vault key")
    }

    /// AC: different intents are independent — dismissing one banner does not
    /// suppress another.
    func testDismiss_isPerIntent_doesNotSuppressOtherBanners() {
        let store = makeStore()

        store.dismiss(.buyVult, now: fixedNow)

        XCTAssertTrue(store.isDismissed(.buyVult, now: fixedNow))
        XCTAssertFalse(store.isDismissed(.followVultisig, now: fixedNow),
                       "Follow banner must stay visible when only buyVult was dismissed")
    }

    /// AC: per-banner TTL. buyVult is 7 days — dismissed at day 6, shown again
    /// at day 8. The boundary (exactly dismissedAt + interval) re-shows.
    func testBuyVultTTL_sevenDayBoundary() {
        let store = makeStore()
        store.dismiss(.buyVult, now: fixedNow)

        XCTAssertTrue(store.isDismissed(.buyVult, now: fixedNow.addingTimeInterval(.days(6))))
        XCTAssertFalse(store.isDismissed(.buyVult, now: fixedNow.addingTimeInterval(.days(7))),
                       "At exactly dismissedAt + TTL the banner re-shows")
        XCTAssertFalse(store.isDismissed(.buyVult, now: fixedNow.addingTimeInterval(.days(8))))
    }

    /// AC: per-banner TTL. upgrade and follow are 15 days.
    func testUpgradeAndFollowTTL_fifteenDayBoundary() {
        let store = makeStore()
        store.dismiss(.upgradeVault, now: fixedNow)
        store.dismiss(.followVultisig, now: fixedNow)

        for banner in [VaultBannerType.upgradeVault, .followVultisig] {
            XCTAssertTrue(store.isDismissed(banner, now: fixedNow.addingTimeInterval(.days(14))))
            XCTAssertFalse(store.isDismissed(banner, now: fixedNow.addingTimeInterval(.days(15))),
                           "At exactly dismissedAt + TTL the banner re-shows")
            XCTAssertFalse(store.isDismissed(banner, now: fixedNow.addingTimeInterval(.days(16))))
        }
    }

    /// AC: an expired dismissal is ignored and the banner shows again
    /// (eligibility permitting).
    func testExpiredDismissal_showsBannerAgain() {
        let store = makeStore()
        let logic = VaultDetailLogic()
        let vault = makeVault(pubKey: "vault-a", chains: [.bitcoin])

        store.dismiss(.buyVult, now: fixedNow)

        let withinTTL = logic.setupBanners(for: vault, store: store, now: fixedNow.addingTimeInterval(.days(6)))
        XCTAssertFalse(withinTTL.contains(.buyVult), "Still suppressed inside the 7-day window")

        let afterTTL = logic.setupBanners(for: vault, store: store, now: fixedNow.addingTimeInterval(.days(8)))
        XCTAssertTrue(afterTTL.contains(.buyVult), "Expired dismissal must let the banner show again")
    }

    /// Backup session rule: dismissed for the rest of the session, but a fresh
    /// store instance (a new cold launch) does not see it — it never persists.
    func testBackupSessionRule_hidesWithinSession_resetsOnNewSession() {
        let defaults = makeDefaults()
        let session1 = makeStore(defaults: defaults)
        let logic = VaultDetailLogic()
        let vault = makeVault(pubKey: "vault-a", chains: [.bitcoin]) // not backed up

        XCTAssertTrue(logic.setupBanners(for: vault, store: session1, now: fixedNow).contains(.backupVault))

        session1.dismiss(.backupVault, now: fixedNow)
        XCTAssertTrue(session1.isDismissed(.backupVault, now: fixedNow))
        XCTAssertFalse(logic.setupBanners(for: vault, store: session1, now: fixedNow).contains(.backupVault),
                       "Backup banner is hidden for the rest of the session after dismissal")

        // New cold launch == new store instance over the SAME persisted defaults.
        let session2 = makeStore(defaults: defaults)
        XCTAssertFalse(session2.isDismissed(.backupVault, now: fixedNow),
                       "Session dismissals never persist, so a new launch re-shows the backup banner")
        XCTAssertTrue(logic.setupBanners(for: vault, store: session2, now: fixedNow).contains(.backupVault))
    }

    /// Eligibility still gates the backup banner: a backed-up vault never shows
    /// it, even before any dismissal.
    func testBackupBanner_backedUpVaultNeverShows() {
        let store = makeStore()
        let logic = VaultDetailLogic()
        let vault = makeVault(pubKey: "vault-a", chains: [.bitcoin])
        vault.isBackedUp = true

        XCTAssertFalse(logic.setupBanners(for: vault, store: store, now: fixedNow).contains(.backupVault),
                       "A backed-up vault must never show the backup reminder")
    }

    // MARK: - Promo banner dismissal: migration

    /// AC: migration is safe. Legacy app-wide `followVultisig` becomes a 15-day
    /// TTL dismissal, suppressed inside the window and shown again after it.
    func testMigration_seedsFollowFromLegacyAppBanners() {
        let store = makeStore()

        store.migrateLegacyDismissals(legacyAppBanners: ["followVultisig"], legacyVaultBanners: [], now: fixedNow)

        XCTAssertTrue(store.isDismissed(.followVultisig, now: fixedNow.addingTimeInterval(.days(14))))
        XCTAssertFalse(store.isDismissed(.followVultisig, now: fixedNow.addingTimeInterval(.days(16))))
    }

    /// AC: per-vault legacy data collapses to global with OR-semantics — a
    /// banner dismissed in any vault is globally suppressed.
    func testMigration_seedsUpgradeAndBuyVultFromVaultUnion() {
        let store = makeStore()
        let logic = VaultDetailLogic()
        let vault = makeVault(pubKey: "vault-x", chains: [.bitcoin])

        store.migrateLegacyDismissals(legacyAppBanners: [],
                                      legacyVaultBanners: ["buyVult", "upgradeVault"],
                                      now: fixedNow)

        XCTAssertTrue(store.isDismissed(.buyVult, now: fixedNow))
        XCTAssertTrue(store.isDismissed(.upgradeVault, now: fixedNow))
        XCTAssertFalse(logic.setupBanners(for: vault, store: store, now: fixedNow).contains(.buyVult))
    }

    /// Legacy `backupVault` dismissal is intentionally NOT carried — backup is
    /// session-scoped and should resurface after upgrade while still missing.
    func testMigration_skipsLegacyBackupDismissal() {
        let store = makeStore()
        let logic = VaultDetailLogic()
        let vault = makeVault(pubKey: "vault-a", chains: [.bitcoin]) // not backed up

        store.migrateLegacyDismissals(legacyAppBanners: [], legacyVaultBanners: ["backupVault"], now: fixedNow)

        XCTAssertFalse(store.isDismissed(.backupVault, now: fixedNow),
                       "Legacy backup dismissal must not carry into the session store")
        XCTAssertTrue(logic.setupBanners(for: vault, store: store, now: fixedNow).contains(.backupVault))
    }

    /// AC: migration runs once and must not reset timestamps. A second run at a
    /// later instant leaves the original countdown intact.
    func testMigration_isIdempotent_doesNotResetTimestamps() {
        let store = makeStore()

        store.migrateLegacyDismissals(legacyAppBanners: [], legacyVaultBanners: ["buyVult"], now: fixedNow)
        // Re-run 3 days later — must NOT restart the 7-day countdown.
        store.migrateLegacyDismissals(legacyAppBanners: [],
                                      legacyVaultBanners: ["buyVult"],
                                      now: fixedNow.addingTimeInterval(.days(3)))

        // 8 days after the FIRST seed it is expired. Had the second run reset
        // the timestamp to day 3, it would still be suppressed here (day 3 + 7).
        XCTAssertFalse(store.isDismissed(.buyVult, now: fixedNow.addingTimeInterval(.days(8))),
                       "Second migration run must not restart the TTL countdown")
    }

    // MARK: - Helpers

    /// A fixed reference instant so TTL boundary math is deterministic.
    private var fixedNow: Date { Date(timeIntervalSince1970: 1_700_000_000) }

    /// A fresh, empty `UserDefaults` domain per call so tests never collide with
    /// each other or with `.standard`.
    private func makeDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
        let suite = "promo-banner-tests-\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeStore(defaults: UserDefaults? = nil) -> PromoBannerDismissalStore {
        PromoBannerDismissalStore(defaults: defaults ?? makeDefaults(), storageKey: "promoBannerDismissals")
    }

    /// Build a Vault populated with native coins for the requested chains.
    /// `chainsWithCoins` is what `VaultDetailLogic.sortedChains(vault:)` reads
    /// to seed the list, so populating `coins` is enough to drive the tests
    /// without touching the network or a SwiftData container.
    private func makeVault(pubKey: String, chains: [Chain]) -> Vault {
        let vault = Vault(
            name: "Vault-\(pubKey)",
            signers: [],
            pubKeyECDSA: pubKey,
            pubKeyEdDSA: "ed-\(pubKey)",
            keyshares: [],
            localPartyID: "party-\(pubKey)",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
        vault.coins = chains.map { makeNativeCoin(pubKey: pubKey, chain: $0) }
        return vault
    }

    private func appendNativeCoin(to vault: Vault, chain: Chain) {
        vault.coins.append(makeNativeCoin(pubKey: vault.pubKeyECDSA, chain: chain))
    }

    private func makeNativeCoin(pubKey: String, chain: Chain) -> Coin {
        makeNativeCoin(pubKey: pubKey, chain: chain, ticker: chain.ticker)
    }

    private func makeNativeCoin(pubKey: String, chain: Chain, ticker: String) -> Coin {
        let meta = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "",
            decimals: 8,
            priceProviderId: "",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: meta, address: "addr-\(pubKey)-\(chain.name)", hexPublicKey: "")
    }
}
