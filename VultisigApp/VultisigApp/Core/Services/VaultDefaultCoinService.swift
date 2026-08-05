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

    /// A coin the pass attached, named by value rather than held by reference.
    ///
    /// Token discovery outlives the call that asks for it, and a live `@Model`
    /// carried across that gap is a reference to something the store may no
    /// longer have: a vault withdrawn after a failed save, deleted by the user,
    /// or dropped by a context reset. Touching one of those traps, and writing
    /// through one persists a vault the caller had already given up on. These
    /// two strings are re-resolved against the store at the moment the work
    /// actually runs, and the work is skipped if they no longer resolve.
    private struct AttachedCoin: Hashable {
        let vaultPubKeyECDSA: String
        let coinID: String
    }

    let context: ModelContext
    private let semaphore = DispatchSemaphore(value: 1)
    private let discoverTokens: @MainActor (Coin, Vault) async -> Void
    private var attachedCoins: [AttachedCoin] = []
    let baseDefaultChains = [Chain.bitcoin, Chain.ethereum, Chain.thorChain, Chain.solana, Chain.bscChain]

    init(
        context: ModelContext,
        discoverTokens: @escaping @MainActor (Coin, Vault) async -> Void = { coin, vault in
            await CoinService.addDiscoveredTokens(nativeToken: coin, to: vault)
        }
    ) {
        self.context = context
        self.discoverTokens = discoverTokens
    }

    /// - Returns: whether the vault holds an attached native coin for every
    ///   default chain this device was asked to build. See
    ///   ``setDefaultCoins(for:)``.
    @discardableResult
    func setDefaultCoinsOnce(vault: Vault) -> Bool {
        semaphore.wait()
        defer {
            semaphore.signal()
        }
        return setDefaultCoins(for: vault)
    }

    /// - Returns: whether the vault holds an attached native coin for every
    ///   default chain this device was asked to build. `false` means the vault
    ///   will open missing at least one chain, which the caller cannot see any
    ///   other way: the rows are written or not written, the save succeeds
    ///   either way, and nothing later in the app rebuilds what this writes.
    ///
    ///   A vault this device can derive nothing for — a legacy key-import vault
    ///   with no `chainPublicKeys` — is `true`, not a failure.
    @discardableResult
    func setDefaultCoins(for vault: Vault) -> Bool {
        // Add default coins when the vault doesn't have any coins in it
        Log.chain.service.info("set default chains to vault")

        let defaultChains = getDefaultChains(for: vault)
        // Nothing to derive is not a failure to derive. A legacy key-import
        // vault predates `chainPublicKeys` and carries none, so this device has
        // nothing to build for it and nothing is missing. Every vault past this
        // line is expected to come out holding coins, and an empty outcome for
        // one of those is the failure this reports.
        guard !defaultChains.isEmpty else { return true }

        // What the vault has to come out holding: the chains it was asked for,
        // never what happened to build. Reading the expectation off the
        // successes is what let the original failure survive its own fix — a
        // `CoinFactory` failure simply left the list, so the postcondition was
        // checked against the survivors, and against none of them it holds
        // vacuously. A vault with no chains in it at all passed as prepared.
        let expectedChains = Set(defaultChains)

        // Answered rather than assumed. A vault that already holds coins is not
        // built again — but *whether it holds every chain it was asked for* is a
        // question about the vault, not about this pass, and an unconditional
        // `true` here is what blesses a half-prepared vault as done and makes
        // the import's retry meaningless.
        guard vault.coins.isEmpty else { return holdsANativeCoin(forEach: expectedChains, in: vault) }

        let chains: [CoinMeta] = TokensStore.TokenSelectionAssets
                .filter { asset in defaultChains.contains(where: { $0 == asset.chain }) }

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
        guard natives.allSatisfy({ attachedIDs.contains($0.id) }) else {
            // The attachment failure, and only it, is all or nothing. A coin
            // that was built and did not attach is a row belonging to no vault
            // — invisible in the app, with nothing left to find it by, and
            // `Coin.id` is not unique so a second pass writes another one
            // beside it. Undone, the vault is exactly as it was found, which is
            // what makes running this again safe.
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

        // Recorded, not started. Only coins that are provably attached get this
        // far, but "attached" is not "stored": the caller's save has not run
        // yet, and until it has, this vault may still be withdrawn.
        // ``startTokenDiscovery()`` is where the work begins.
        attachedCoins.append(
            contentsOf: inserted.map {
                AttachedCoin(vaultPubKeyECDSA: vault.pubKeyECDSA, coinID: $0.id)
            }
        )

        // A chain that could not be *built* is reported and not undone, and the
        // difference from the case above is the whole reason they are separate.
        // Nothing was written for it, so there is no orphan row to take back —
        // and keygen ignores this answer, so undoing here would cost a vault
        // with one bad key every chain it *could* derive, to report a chain it
        // could not. Partial beats empty when nothing rebuilds either.
        return holdsANativeCoin(forEach: expectedChains, in: vault)
    }

    /// Whether every one of `chains` has a native coin attached to the vault.
    ///
    /// Read from `vault.coins` rather than from anything this pass built, so it
    /// answers the same question for a vault that arrived already holding coins
    /// as for one this pass just filled.
    private func holdsANativeCoin(forEach chains: Set<Chain>, in vault: Vault) -> Bool {
        chains.isSubset(of: Set(vault.coins.filter(\.isNativeToken).map(\.chain)))
    }

    /// Starts discovering held tokens for the coins this service attached, and
    /// forgets them so a second call cannot start the same work twice.
    ///
    /// Call it once the save that stores those coins has **succeeded**. It is
    /// deliberately not started from ``setDefaultCoins(for:)``: discovery is
    /// unstructured work that outlives the call, suspends on the network, and
    /// then writes through `Storage.shared`. Started before the save, it can
    /// come back and persist a vault whose save failed and which the caller has
    /// already withdrawn — turning a refused keygen or a rolled-back import into
    /// a stored one. A caller whose save threw simply never calls this.
    ///
    /// That leaves what can happen *after* a successful save — the user deletes
    /// the vault, a rollback takes the coins back, the context is reset — which
    /// is why nothing live is carried across the gap. Every coin is re-resolved
    /// from the store immediately before its own discovery runs, and one that no
    /// longer resolves, or is no longer this vault's, is skipped.
    ///
    /// - Returns: the task doing the work, so a caller that needs to observe it
    ///   can wait. Production discards it.
    @MainActor
    @discardableResult
    func startTokenDiscovery() -> Task<Void, Never> {
        var seen: Set<AttachedCoin> = []
        // A retried preparation records the same coin twice; discovery is
        // idempotent but the round trip is not free.
        let pending = attachedCoins.filter { seen.insert($0).inserted }
        attachedCoins = []

        return Task {
            for attached in pending {
                guard let (vault, coin) = stored(attached) else {
                    Log.chain.service.info("Skipping token discovery: the coin is no longer stored against its vault")
                    continue
                }
                await discoverTokens(coin, vault)
            }
        }
    }

    /// The vault and coin an ``AttachedCoin`` names, or `nil` if the store no
    /// longer holds them related that way.
    ///
    /// The vault is fetched by its unique key rather than kept, and the coin is
    /// looked up *through* the vault, so this answers existence and the
    /// relationship in one step — which is the pair of facts discovery needs and
    /// the pair the original failure lost.
    @MainActor
    private func stored(_ attached: AttachedCoin) -> (Vault, Coin)? {
        let pubKeyECDSA = attached.vaultPubKeyECDSA
        var descriptor = FetchDescriptor<Vault>(
            predicate: #Predicate<Vault> { $0.pubKeyECDSA == pubKeyECDSA }
        )
        descriptor.fetchLimit = 1
        guard let vault = try? context.fetch(descriptor).first,
              let coin = vault.coins.first(where: { $0.id == attached.coinID }) else {
            return nil
        }
        return (vault, coin)
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
