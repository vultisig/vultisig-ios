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

    // MARK: - Helpers

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
