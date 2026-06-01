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

private let logger = Logger(subsystem: "com.vultisig.app", category: "vult-tier-service")

struct VultTierService {
    let vultTicker = "VULT"
    let thorguardContractAddress = "0xa98b29a8f5a247802149c268ecf860b8308b7291"

    @AppStorage("vult_balance_cache") private var cacheEntries: [CacheEntry] = []
    private static let cacheValidityDuration: TimeInterval = 3 * 60 // 3 minutes

    /// Process-lifetime, per-wallet cache of the fully-resolved discount tier
    /// (VULT balance result + Thorguard boost). The tier doesn't change during a
    /// swap session, so once resolved it's read back without re-running the
    /// Thorguard NFT `eth_call` on every quote fetch.
    private static let sessionCache = SessionTierCache()

    func fetchDiscountTier(for vault: Vault, cached: Bool = false) async -> VultDiscountTier? {
        let balance = cached ? (getVultToken(for: vault)?.balanceDecimal ?? 0) : await fetchVultBalance(for: vault)
        var tier = VultDiscountTier.allCases
            .sorted { $0.balanceToUnlock > $1.balanceToUnlock }
            .first { balance >= $0.balanceToUnlock }

        // Check for Thorguard boost (upgrade tier by one level if eligible)
        if canUpgrade(tier) {
            let hasThorguard = await checkThorguardBalance(for: vault)
            if hasThorguard {
                tier = upgradeTier(tier)
                logger.info("Upgraded VULT Tier to \(tier?.name ?? "", privacy: .public)")
            }
        }

        return tier
    }

    /// Resolves the discount tier once per wallet for the session and caches the
    /// fully-resolved value (post-Thorguard). Subsequent calls return the cached
    /// tier without any network access, keeping the Thorguard `eth_call` off the
    /// per-quote critical path.
    func resolveTierForSession(for vault: Vault) async -> VultDiscountTier? {
        let vaultId = vault.pubKeyEdDSA
        return await Self.sessionCache.resolve(for: vaultId) {
            await fetchDiscountTier(for: vault)
        }
    }

    /// Drops the session-cached resolved tier for a vault, forcing the next
    /// `resolveTierForSession` to re-resolve from the network.
    func clearSessionTier(for vault: Vault) async {
        await Self.sessionCache.clear(for: vault.pubKeyEdDSA)
    }

    func getVultToken(for vault: Vault) -> Coin? {
        vault.coins.first(where: { $0.chain == .ethereum && $0.ticker == vultTicker })
    }

    /// Clears the cached timestamp for a specific vault
    func clearCache(for vault: Vault) {
        cacheEntries.removeAll { $0.vaultId == vault.pubKeyEdDSA }
    }

    /// Clears all cached timestamps
    func clearAllCache() {
        cacheEntries.removeAll()
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

    /// Upgrades a tier to the next level (capped at Platinum for Thorguard boost)
    private func upgradeTier(_ tier: VultDiscountTier?) -> VultDiscountTier {
        guard let tier else { return .bronze }
        let tiers = VultDiscountTier.allCases
        let index = tiers.firstIndex(of: tier)
        if let index {
            return tiers[safe: index + 1] ?? tier
        } else {
            return tier
        }
    }

    private func canUpgrade(_ tier: VultDiscountTier?) -> Bool {
        switch tier {
        case .bronze, .silver, .gold, .none:
            logger.debug("Can upgrade VULT Tier, currently \(tier?.name ?? "", privacy: .public)")
            return true
        case .platinum, .diamond, .ultimate:
            logger.debug("Cannot upgrade VULT Tier, currently \(tier?.name ?? "", privacy: .public)")
            return false
        }
    }

    /// Checks if the vault holds at least one Thorguard NFT
    private func checkThorguardBalance(for vault: Vault) async -> Bool {
        // Find Ethereum address in the vault
        guard let ethCoin = vault.coins.first(where: { $0.chain == .ethereum }) else {
            return false
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
            return false
        }
    }
}

private extension VultTierService {
    struct CacheEntry: Codable {
        let vaultId: String
        let lastFetchDate: Date
    }

    func fetchVultBalance(for vault: Vault) async -> Decimal {
        // Check if we need to fetch fresh balance
        if shouldFetchBalance(for: vault) {
            // Fetch fresh balance
            await addEthChainIfNeeded(for: vault)
            let vultToken = await getOrAddVultTokenIfNeeded(to: vault)
            if let vultToken {
                await BalanceService.shared.updateBalance(for: vultToken)
            }

            // Update the cache entry
            cacheEntries.removeAll { $0.vaultId == vault.pubKeyEdDSA }
            cacheEntries.append(CacheEntry(vaultId: vault.pubKeyEdDSA, lastFetchDate: Date()))
        }

        // Return the balance from the coin (fresh or cached)
        guard let vultToken = getVultToken(for: vault) else { return .zero }
        return vultToken.balanceDecimal
    }

    func getOrAddVultTokenIfNeeded(to vault: Vault) async -> Coin? {
        var vultToken = getVultToken(for: vault)
        if vultToken == nil {
            await addVultToken(to: vault)
            vultToken = getVultToken(for: vault)
        }

        return vultToken
    }

    func addVultToken(to vault: Vault) async {
        let vultTokenMeta = TokensStore.TokenSelectionAssets.first(where: { $0.chain == .ethereum && $0.ticker == vultTicker })
        guard let vultTokenMeta else { return }
        try? await CoinService.addToChain(assets: [vultTokenMeta], to: vault)
    }

    func addEthChainIfNeeded(for vault: Vault) async {
        guard !vault.coins.contains(where: { $0.chain == .ethereum && $0.isNativeToken }) else {
            return
        }

        let ethNativeToken = TokensStore.TokenSelectionAssets.first(where: { $0.chain == .ethereum && $0.isNativeToken })
        guard let ethNativeToken else { return }
        try? await CoinService.addToChain(assets: [ethNativeToken], to: vault)
    }
}

/// Thread-safe, in-memory cache of resolved discount tiers keyed by vault id.
/// `Box` lets us distinguish "not yet resolved" (no entry) from "resolved to
/// nil" (entry holding nil) so a genuinely tier-less wallet isn't re-resolved.
///
/// Resolution is single-flight: concurrent callers for the same vault (e.g. the
/// fire-and-forget warm-up on screen load racing the first debounced quote
/// fetch) await one shared `Task` instead of each launching their own
/// `fetchDiscountTier` — so the underlying Thorguard `eth_call` runs at most
/// once per vault per session.
actor SessionTierCache {
    struct Box {
        let value: VultDiscountTier?
    }

    private var tiers: [String: Box] = [:]
    private var inFlight: [String: Task<VultDiscountTier?, Never>] = [:]

    /// Returns the cached tier if resolved; otherwise runs `work` once, sharing
    /// the in-flight `Task` with any concurrent caller for the same vault.
    /// `work` must not capture `@Model` types — pass value-type inputs only.
    func resolve(
        for vaultId: String,
        _ work: @Sendable @escaping () async -> VultDiscountTier?
    ) async -> VultDiscountTier? {
        if let box = tiers[vaultId] {
            return box.value
        }
        if let task = inFlight[vaultId] {
            return await task.value
        }
        let task = Task { await work() }
        inFlight[vaultId] = task
        let value = await task.value
        tiers[vaultId] = Box(value: value)
        inFlight[vaultId] = nil
        return value
    }

    func clear(for vaultId: String) {
        tiers[vaultId] = nil
        inFlight[vaultId] = nil
    }
}
