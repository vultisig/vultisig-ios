//
//  VultBalanceService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/10/2025.
//

import BigInt
import Foundation
import OSLog
import SwiftUI

private let logger = Log.app.service

struct VultTierService {
    /// VULT's ERC-20 contract on Ethereum. The tier is matched on this rather
    /// than on the "VULT" ticker: any address can deploy a token under any
    /// symbol and a user can add it to their vault, and a look-alike must not
    /// buy a real trading-fee discount.
    static let vultContractAddress = "0xb788144DF611029C60b859DF47e79B7726C4DEBa"
    let thorguardContractAddress = "0xa98b29a8f5a247802149c268ecf860b8308b7291"

    @AppStorage("vult_balance_cache") private var cacheEntries: [CacheEntry] = []
    private static let cacheValidityDuration: TimeInterval = 3 * 60 // 3 minutes

    /// Per-vault session cache of Thorguard NFT ownership — and *only* that.
    ///
    /// Ownership is the expensive half of a tier resolution (an Ethereum
    /// `eth_call` that would otherwise fire on every debounced keystroke) and
    /// the half that cannot change without the user leaving the app, so it is
    /// the only half worth pinning for the process lifetime. The VULT balance
    /// half is deliberately *not* cached: it arrives late, can fail, and is
    /// refreshed by unrelated screens, so caching a fully-resolved tier meant a
    /// single balance read of zero cost the user their fee discount on every
    /// swap for the rest of the session.
    private static let thorguardCache = ThorguardOwnershipCache()

    /// One in-flight VULT balance refresh per vault. The swap screen warms the
    /// tier on load while the first debounced quote resolves it again moments
    /// later; without this they'd each pay for their own round trip.
    @MainActor
    private static var refreshesInFlight: [String: Task<Bool, Never>] = [:]

    // MARK: - Tier resolution

    /// Resolves the tier with a live Thorguard check. `cached` selects the VULT
    /// balance source: `true` reads the balance already stored on the vault,
    /// `false` refreshes it from the network first (throttled to once per
    /// `cacheValidityDuration`).
    ///
    /// `@MainActor` because it reads and writes the `@Model` vault and its coins.
    @MainActor
    func fetchDiscountTier(for vault: Vault, cached: Bool = false) async -> VultDiscountTier? {
        let balance = cached ? storedVultBalance(for: vault) : await fetchVultBalance(for: vault)
        let base = Self.baseTier(forBalance: balance)
        // Skip the eth_call entirely when the boost couldn't lift the tier anyway.
        guard Self.canUpgrade(base) else { return base }
        return Self.applyThorguardBoost(to: base, hasThorguard: await checkThorguardBalance(for: vault))
    }

    /// Quote-path resolution. The VULT balance is re-read on every call, so a
    /// balance that lands late — or a first read that failed — is picked up by
    /// the very next quote instead of being pinned for the session. Only the
    /// Thorguard `eth_call` behind it is session-cached, which is what keeps it
    /// off the per-quote critical path.
    @MainActor
    func resolveTierForSession(for vault: Vault) async -> VultDiscountTier? {
        await Self.resolveSessionTier(
            cache: Self.thorguardCache,
            vaultId: vault.pubKeyEdDSA,
            balance: { await fetchVultBalance(for: vault) },
            ownership: { await checkThorguardBalance(for: vault) }
        )
    }

    /// The session-scoped composition, kept free of vault plumbing so it can be
    /// exercised without a network: `balance` is asked on every call, while
    /// ownership goes through `cache`, which remembers only a determined answer.
    @MainActor
    static func resolveSessionTier(
        cache: ThorguardOwnershipCache,
        vaultId: String,
        balance: @MainActor () async -> Decimal,
        ownership: @MainActor @escaping () async -> Bool?
    ) async -> VultDiscountTier? {
        let base = baseTier(forBalance: await balance())
        guard canUpgrade(base) else { return base }
        let hasThorguard = await cache.ownsThorguard(for: vaultId, ownership)
        return applyThorguardBoost(to: base, hasThorguard: hasThorguard)
    }

    /// Highest tier unlocked by `balance` alone, before any Thorguard boost.
    static func baseTier(forBalance balance: Decimal) -> VultDiscountTier? {
        VultDiscountTier.allCases
            .sorted { $0.balanceToUnlock > $1.balanceToUnlock }
            .first { balance >= $0.balanceToUnlock }
    }

    /// Tier for a VULT balance combined with Thorguard ownership. Pass `nil` for
    /// `hasThorguard` when ownership could not be determined.
    static func tier(forBalance balance: Decimal, hasThorguard: Bool?) -> VultDiscountTier? {
        applyThorguardBoost(to: baseTier(forBalance: balance), hasThorguard: hasThorguard)
    }

    func getVultToken(for vault: Vault) -> Coin? {
        vault.coins.first { Self.isVult($0) }
    }

    /// Whether `coin` is the real VULT, matched on chain + contract address.
    /// Contract addresses are compared case-insensitively: EIP-55 checksums a
    /// hex address by letter case, so the same token legitimately arrives in
    /// different casings depending on where its metadata came from.
    private static func isVult(_ coin: Coin) -> Bool {
        coin.chain == .ethereum
            && coin.contractAddress.caseInsensitiveCompare(vultContractAddress) == .orderedSame
    }

    private static func isVult(_ meta: CoinMeta) -> Bool {
        meta.chain == .ethereum
            && meta.contractAddress.caseInsensitiveCompare(vultContractAddress) == .orderedSame
    }

    /// Checks if we recently fetched the balance (within cache validity duration)
    func shouldFetchBalance(for vault: Vault) -> Bool {
        guard let cacheEntry = cacheEntries.first(where: { $0.vaultId == vault.pubKeyEdDSA }) else {
            logger.debug("Getting $VULT balance from network")
            return true
        }
        let shouldFetch = Date().timeIntervalSince(cacheEntry.lastFetchDate) >= Self.cacheValidityDuration
        logger.debug("Getting $VULT balance from cache: \(shouldFetch)")
        return shouldFetch
    }

    /// Applies the one-level Thorguard boost. `hasThorguard == nil` means
    /// ownership couldn't be determined; it is treated as "no boost" for this
    /// resolution only and deliberately never remembered, so the next
    /// resolution retries instead of locking the user out of the upgrade.
    private static func applyThorguardBoost(
        to base: VultDiscountTier?,
        hasThorguard: Bool?
    ) -> VultDiscountTier? {
        guard hasThorguard == true, canUpgrade(base) else { return base }
        let upgraded = upgradeTier(base)
        logger.info("Upgraded VULT Tier to \(upgraded.name, privacy: .public)")
        return upgraded
    }

    /// Upgrades a tier to the next level (capped at Platinum for Thorguard boost)
    private static func upgradeTier(_ tier: VultDiscountTier?) -> VultDiscountTier {
        guard let tier else { return .bronze }
        let tiers = VultDiscountTier.allCases
        let index = tiers.firstIndex(of: tier)
        if let index {
            return tiers[safe: index + 1] ?? tier
        } else {
            return tier
        }
    }

    private static func canUpgrade(_ tier: VultDiscountTier?) -> Bool {
        switch tier {
        case .bronze, .silver, .gold, .none:
            logger.debug("Can upgrade VULT Tier, currently \(tier?.name ?? "", privacy: .public)")
            return true
        case .platinum, .diamond, .ultimate:
            logger.debug("Cannot upgrade VULT Tier, currently \(tier?.name ?? "", privacy: .public)")
            return false
        }
    }

    /// Whether the vault holds at least one Thorguard NFT. Returns `nil` when
    /// ownership could not be determined — no Ethereum address on the vault yet,
    /// or a failed `eth_call`. Callers must not remember `nil` as "no NFT".
    @MainActor
    private func checkThorguardBalance(for vault: Vault) async -> Bool? {
        // Find Ethereum address in the vault
        guard let ethCoin = vault.coins.first(where: { $0.chain == .ethereum }) else {
            logger.debug("No Ethereum address on the vault, THORGuard ownership unknown")
            return nil
        }

        do {
            let evmService = try EvmService.getService(forChain: .ethereum)
            let balance = try await evmService.fetchERC20TokenBalance(
                contractAddress: thorguardContractAddress,
                walletAddress: ethCoin.address
            )
            logger.debug("THORGuards balance is \(balance) for \(ethCoin.address)")
            return balance > 0
        } catch {
            logger.error("Error fetching Thorguard balance: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

private extension VultTierService {
    struct CacheEntry: Codable {
        let vaultId: String
        let lastFetchDate: Date
    }

    /// VULT balance already stored on the vault — an in-memory read, no network.
    func storedVultBalance(for vault: Vault) -> Decimal {
        getVultToken(for: vault)?.balanceDecimal ?? 0
    }

    @MainActor
    func fetchVultBalance(for vault: Vault) async -> Decimal {
        // Check if we need to fetch fresh balance
        if shouldFetchBalance(for: vault) {
            let vaultId = vault.pubKeyEdDSA
            let didLand: Bool
            if let inFlight = Self.refreshesInFlight[vaultId] {
                didLand = await inFlight.value
            } else {
                let refresh = Task { @MainActor in await refreshVultBalance(for: vault) }
                Self.refreshesInFlight[vaultId] = refresh
                didLand = await refresh.value
                Self.refreshesInFlight[vaultId] = nil
            }

            // Stamp the freshness cache only when a live balance actually
            // landed. Stamping after a failed fetch would suppress every retry
            // for the next three minutes, leaving the tier resolved from a
            // balance that was never read.
            if didLand {
                cacheEntries.removeAll { $0.vaultId == vaultId }
                cacheEntries.append(CacheEntry(vaultId: vaultId, lastFetchDate: Date()))
            }
        }

        return storedVultBalance(for: vault)
    }

    /// Refreshes the vault's VULT balance from the network, adding the Ethereum
    /// chain and the VULT token first if the vault doesn't carry them yet.
    /// Returns whether a live balance landed.
    @MainActor
    func refreshVultBalance(for vault: Vault) async -> Bool {
        await addEthChainIfNeeded(for: vault)
        guard let vultToken = await getOrAddVultTokenIfNeeded(to: vault) else { return false }
        return await BalanceService.shared.updateBalance(for: vultToken)
    }

    @MainActor
    func getOrAddVultTokenIfNeeded(to vault: Vault) async -> Coin? {
        var vultToken = getVultToken(for: vault)
        if vultToken == nil {
            await addVultToken(to: vault)
            vultToken = getVultToken(for: vault)
        }

        return vultToken
    }

    @MainActor
    func addVultToken(to vault: Vault) async {
        let vultTokenMeta = TokensStore.TokenSelectionAssets.first { Self.isVult($0) }
        guard let vultTokenMeta else { return }
        try? await CoinService.addToChain(assets: [vultTokenMeta], to: vault)
    }

    @MainActor
    func addEthChainIfNeeded(for vault: Vault) async {
        guard !vault.coins.contains(where: { $0.chain == .ethereum && $0.isNativeToken }) else {
            return
        }

        let ethNativeToken = TokensStore.TokenSelectionAssets.first(where: { $0.chain == .ethereum && $0.isNativeToken })
        guard let ethNativeToken else { return }
        try? await CoinService.addToChain(assets: [ethNativeToken], to: vault)
    }
}

/// Thread-safe, in-memory record of whether a vault holds a Thorguard NFT,
/// keyed by vault id and held for the process lifetime.
///
/// Only a *determined* answer is stored. "Couldn't check" — a failed `eth_call`,
/// or a vault with no Ethereum address yet — is returned to the caller as `nil`
/// but never cached, so the next resolution retries instead of pinning a wrong
/// "no NFT" for the rest of the session.
///
/// Lookups are single-flight: concurrent callers for the same vault (e.g. the
/// fire-and-forget warm-up on swap-screen load racing the first debounced quote
/// fetch) await one shared `Task` instead of each firing their own `eth_call` —
/// so the call runs at most once per vault per session.
actor ThorguardOwnershipCache {
    private var owned: [String: Bool] = [:]
    private var inFlight: [String: Task<Bool?, Never>] = [:]

    /// Returns the cached ownership flag, or runs `check` once and shares its
    /// in-flight `Task` with any concurrent caller for the same vault.
    /// `check` is `@MainActor`-isolated so it can safely read the `@Model` vault
    /// it resolves ownership from — nothing non-Sendable crosses the actor's
    /// executor boundary.
    func ownsThorguard(
        for vaultId: String,
        _ check: @MainActor @escaping () async -> Bool?
    ) async -> Bool? {
        if let owned = owned[vaultId] {
            return owned
        }
        if let task = inFlight[vaultId] {
            return await task.value
        }
        let task = Task { @MainActor in await check() }
        inFlight[vaultId] = task
        let value = await task.value
        inFlight[vaultId] = nil
        if let value {
            owned[vaultId] = value
        }
        return value
    }
}
