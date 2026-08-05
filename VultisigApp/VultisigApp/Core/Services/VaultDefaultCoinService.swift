//
//  VaultDefaultCoinService.swift
//  VultisigApp
//
//  Created by Johnny Luo on 3/6/2024.
//

import Foundation
import SwiftData
import OSLog

class VaultDefaultCoinService {
    let context: ModelContext
    private let semaphore = DispatchSemaphore(value: 1)
    let baseDefaultChains = [Chain.bitcoin, Chain.ethereum, Chain.thorChain, Chain.solana, Chain.bscChain]

    init(context: ModelContext) {
        self.context = context
    }

    /// - Returns: whether the vault holds a native coin for every default chain
    ///   this device was asked to build. See ``setDefaultCoins(for:)``.
    @discardableResult
    func setDefaultCoinsOnce(vault: Vault) -> Bool {
        semaphore.wait()
        defer {
            semaphore.signal()
        }
        return setDefaultCoins(for: vault)
    }

    /// - Returns: whether the vault holds a native coin for every default chain
    ///   this device was asked to build. `false` means the vault will open with
    ///   chains missing, which the caller cannot see any other way: the rows are
    ///   written or not written, the save succeeds either way, and nothing later
    ///   in the app rebuilds what this writes.
    ///
    ///   A vault this device can derive nothing for — a legacy key-import vault
    ///   with no `chainPublicKeys` — is `true`, not a failure. So is a vault
    ///   that already had coins.
    @discardableResult
    func setDefaultCoins(for vault: Vault) -> Bool {
        // Add default coins when the vault doesn't have any coins in it
        Log.chain.service.info("set default chains to vault")
        guard vault.coins.isEmpty else { return true }

        let defaultChains = getDefaultChains(for: vault)
        // Nothing to derive is not a failure to derive. A legacy key-import
        // vault predates `chainPublicKeys` and carries none, so this device has
        // nothing to build for it and nothing is missing. Every vault past this
        // line is expected to come out holding coins, and an empty outcome for
        // one of those is the failure this reports.
        guard !defaultChains.isEmpty else { return true }

        let chains: [CoinMeta] = TokensStore.TokenSelectionAssets
                .filter { asset in defaultChains.contains(where: { $0 == asset.chain }) }

        // What the vault has to come out holding, read off the chains asked for
        // and never off what happened to build. Reading it off the successes is
        // what let the original failure survive its own fix: a `CoinFactory`
        // failure simply left the list, so the postcondition was checked against
        // the survivors — and against none of them it holds vacuously, which
        // means a vault with no chains in it at all passed as prepared.
        let expectedChains = Set(chains.filter(\.isNativeToken).map(\.chain))
        guard !expectedChains.isEmpty else {
            Log.chain.service.error("No native asset to build for any default chain of \(vault.name, privacy: .public)")
            return false
        }

        var coins: [Coin] = []
        for asset in chains {
            let pubKey = vault.chainPublicKeys.first { $0.chain == asset.chain }?.publicKeyHex
            let isDerived = pubKey != nil
            do {
                coins.append(
                    try CoinFactory.create(
                        asset: asset,
                        publicKeyECDSA: pubKey ?? vault.pubKeyECDSA,
                        publicKeyEdDSA: pubKey ?? vault.pubKeyEdDSA,
                        hexChainCode: vault.hexChainCode,
                        isDerived: isDerived,
                        publicKeyMLDSA44: vault.publicKeyMLDSA44
                    )
                )
            } catch {
                // Kept rather than dropped. A `try?` here is indistinguishable
                // from a chain that was never asked for, and a chain that cannot
                // be built is a chain the user will not have.
                Log.chain.service.error("Could not build \(asset.ticker, privacy: .public) on \(asset.chain.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        let natives = coins.filter(\.isNativeToken)
        var inserted: [Coin] = []
        for coin in natives where !vault.coins.contains(where: { $0.id == coin.id }) {
            self.context.insert(coin)

            // Attach from the coin's side. Writing the to-many side instead —
            // `vault.coins.append(coin)` — only works while the vault is still
            // unsaved: once it has been through a `save()`, appending a coin
            // that is itself still a temporary object does not register on the
            // vault at all. The relationship re-faults to its persisted value,
            // and the next save writes that back over the inverse the append
            // had set, leaving the coin rows on disk with no vault and the
            // vault with no chains. `CoinService.addToChain` sidesteps the same
            // trap by saving the coin before appending; here there is no save
            // to hang that on, and the to-one write is what survives either
            // way. Do not "simplify" this back to an append.
            coin.vault = vault
            inserted.append(coin)
        }

        // Enable default Defi chains
        let previousDefiChains = vault.defiChains
        vault.defiChains = Array(Set(coins.map(\.chain).filter { CoinAction.defiChains.contains($0) }))

        let attachedIDs = Set(vault.coins.map(\.id))
        let attachedChains = Set(vault.coins.filter(\.isNativeToken).map(\.chain))
        // Two separate ways this pass can come up short, and neither is visible
        // in the other. A coin that was built and did not attach; and a chain
        // whose coin was never built at all.
        guard natives.allSatisfy({ attachedIDs.contains($0.id) }),
              expectedChains.isSubset(of: attachedChains) else {
            // All of it or none of it. A coin that did not attach is a row
            // belonging to no vault — invisible in the app and with nothing
            // left to find it by — and a vault left holding *some* of its coins
            // is worse still: the `coins.isEmpty` guard above would read it as
            // already prepared and never look again. Undone, `false` means the
            // vault is exactly as it was found, which is the whole reason
            // running this again is safe.
            for coin in inserted {
                // Detached from the coin's side before the delete, for the same
                // reason it was attached from that side: the to-one write is the
                // one that takes on a vault that has been through a `save()`.
                coin.vault = nil
                context.delete(coin)
            }
            vault.defiChains = previousDefiChains
            return false
        }

        // Only over coins that are provably attached. Token discovery is
        // unstructured work that outlives this call, and pointing it at a coin
        // that is about to be withdrawn is the same mistake the import's own
        // ordering exists to avoid.
        for coin in inserted {
            Task {
                await CoinService.addDiscoveredTokens(nativeToken: coin, to: vault)
            }
        }

        return true
    }

    func getDefaultChains(for vault: Vault) -> [Chain] {
        // For KeyImport we can only add derived chains
        if vault.libType == .KeyImport {
            return vault.chainPublicKeys.map(\.chain)
        } else {
            return baseDefaultChains
        }
    }
}
