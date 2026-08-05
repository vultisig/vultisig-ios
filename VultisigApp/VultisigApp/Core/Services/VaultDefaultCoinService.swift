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

    /// - Returns: whether the vault holds every default coin this device could
    ///   derive for it. See ``setDefaultCoins(for:)``.
    @discardableResult
    func setDefaultCoinsOnce(vault: Vault) -> Bool {
        semaphore.wait()
        defer {
            semaphore.signal()
        }
        return setDefaultCoins(for: vault)
    }

    /// - Returns: whether the vault holds every default coin this device could
    ///   derive for it. `false` means the coins were built but did not attach,
    ///   which the caller cannot see any other way: the rows are written, the
    ///   save succeeds, and the vault opens with no chains in it.
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
        let chains: [CoinMeta] = TokensStore.TokenSelectionAssets
                .filter { asset in defaultChains.contains(where: { $0 == asset.chain }) }

        let coins = chains
            .compactMap { c in
                let pubKey = vault.chainPublicKeys.first { $0.chain == c.chain}?.publicKeyHex
                let isDerived = pubKey != nil
                return try? CoinFactory.create(
                    asset: c,
                    publicKeyECDSA: pubKey ?? vault.pubKeyECDSA,
                    publicKeyEdDSA: pubKey ?? vault.pubKeyEdDSA,
                    hexChainCode: vault.hexChainCode,
                    isDerived: isDerived,
                    publicKeyMLDSA44: vault.publicKeyMLDSA44
                )
            }

        let natives = coins.filter(\.isNativeToken)
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

            Task {
                await CoinService.addDiscoveredTokens(nativeToken: coin, to: vault)
            }
        }

        // Enable default Defi chains
        vault.defiChains = Array(Set(coins.map(\.chain).filter { CoinAction.defiChains.contains($0) }))

        let attached = Set(vault.coins.map(\.id))
        return natives.allSatisfy { attached.contains($0.id) }
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
