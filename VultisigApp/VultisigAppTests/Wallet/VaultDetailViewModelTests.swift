//
//  VaultDetailViewModelTests.swift
//  VultisigAppTests
//
//  Regression tests for the `chains.isEmpty || chainsVaultPubKeyECDSA !=
//  vault.pubKeyECDSA` seed guard in `VaultDetailViewModel.updateBalance(vault:)`.
//
//  The earlier `chains.isEmpty` guard was vault-blind: after switching vaults
//  the cached list still belonged to the previous vault, so the synchronous
//  seed was skipped and the wallet tab kept rendering stale chains until the
//  async refresh landed (~250ms debounce + network round trip). These tests
//  pin the fix and the invariants it must preserve:
//
//    1. First call on an empty model seeds synchronously.
//    2. Switching to a different vault re-seeds synchronously, even with a
//       non-empty `chains` array.
//    3. Same-vault calls do *not* re-seed — preserves the prior fix for the
//       visible "stale-then-fresh" double reorder on post-swap refreshes.
//    4. `groupChains(vault:)` keeps the identity tracker in sync so a
//       subsequent same-vault `updateBalance` call still skips the seed.
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
        XCTAssertFalse(vm.chains.contains(where: { vaultA.chainsWithCoins.contains($0) && !vaultB.chainsWithCoins.contains($0) }),
                       "Stale chains from vault A must not survive the switch to vault B")
    }

    /// Calling `updateBalance` repeatedly against the same vault must not
    /// re-seed `chains`. The "stale-then-fresh" double reorder this gate was
    /// originally added to prevent depends on this invariant — the seed only
    /// fires on identity change, not on every refresh.
    func testUpdateBalance_sameVaultRefresh_doesNotReSeedChains() {
        let vault = makeVault(pubKey: "vault-a", chains: [.bitcoin, .ethereum])
        let vm = VaultDetailViewModel()

        vm.updateBalance(vault: vault)
        // Mutate the array in a way that the seed would clobber. If the
        // second call re-seeds, this sentinel disappears.
        let sentinel: [Chain] = [.dydx]
        vm.chains = sentinel

        vm.updateBalance(vault: vault)

        XCTAssertEqual(vm.chains, sentinel,
                       "Same-vault updateBalance must not synchronously re-seed chains")
    }

    /// `groupChains(vault:)` is another seed site. It must update the identity
    /// tracker so a subsequent `updateBalance(vault:)` call against the same
    /// vault hits the skip branch (no double seed).
    func testGroupChains_updatesIdentityTracker_soSameVaultUpdateDoesNotReSeed() {
        let vault = makeVault(pubKey: "vault-a", chains: [.bitcoin, .ethereum])
        let vm = VaultDetailViewModel()

        vm.groupChains(vault: vault)
        let sentinel: [Chain] = [.dydx]
        vm.chains = sentinel

        vm.updateBalance(vault: vault)

        XCTAssertEqual(vm.chains, sentinel,
                       "updateBalance after groupChains for the same vault must not re-seed")
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
        vault.coins = chains.map { chain in
            let meta = CoinMeta(
                chain: chain,
                ticker: chain.ticker,
                logo: "",
                decimals: 8,
                priceProviderId: "",
                contractAddress: "",
                isNativeToken: true
            )
            return Coin(asset: meta, address: "addr-\(pubKey)-\(chain.name)", hexPublicKey: "")
        }
        return vault
    }
}
