//
//  VultBalanceService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/10/2025.
//

import BigInt
import Foundation
import SwiftUI

struct VultTierService {
    let vultTicker = "VULT"
    let thorguardContractAddress = "0xa98b29a8f5a247802149c268ecf860b8308b7291"

    @AppStorage("vult_balance_cache") private var cacheEntries: [CacheEntry] = []
    private static let cacheValidityDuration: TimeInterval = 3 * 60 // 3 minutes

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
                print("Upgraded VULT Tier to ", tier?.name ?? "")
            }
        }

        return tier
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
            print("Getting $VULT balance from network")
            return true
        }
        let shouldFetch = Date().timeIntervalSince(cacheEntry.lastFetchDate) >= Self.cacheValidityDuration
        print("Getting $VULT balance from cache:", shouldFetch)
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
            print("Can upgrade VULT Tier, currently \(tier?.name ?? "")")
            return true
        case .platinum, .diamond, .ultimate:
            print("Cannot upgrade VULT Tier, currently \(tier?.name ?? "")")
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
            print("THORGuards balance is \(balance) for \(ethCoin.address)")
            return balance > 0
        } catch {
            print("Error fetching Thorguard balance: \(error.localizedDescription)")
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
        try? await CoinService.shared.addToChain(assets: [vultTokenMeta], to: vault)
    }

    func addEthChainIfNeeded(for vault: Vault) async {
        guard !vault.coins.contains(where: { $0.chain == .ethereum && $0.isNativeToken }) else {
            return
        }

        let ethNativeToken = TokensStore.TokenSelectionAssets.first(where: { $0.chain == .ethereum && $0.isNativeToken })
        guard let ethNativeToken else { return }
        try? await CoinService.shared.addToChain(assets: [ethNativeToken], to: vault)
    }
}
