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
    
    @AppStorage("vult_balance_cache") private static var cacheEntries: [CacheEntry] = []
    private static let cacheValidityDuration: TimeInterval = 5 * 60 // 5 minutes
    
    func fetchDiscountTier(for vault: Vault) async -> VultDiscountTier? {
        let balance = await fetchVultBalance(for: vault)
        return VultDiscountTier.allCases
            .sorted { $0.balanceToUnlock > $1.balanceToUnlock }
            .first { balance >= $0.balanceToUnlock }
    }
    
    func getVultToken(for vault: Vault) -> Coin? {
        vault.coins.first(where: { $0.chain == .ethereum && $0.ticker == vultTicker })
    }
    
    /// Clears the cached timestamp for a specific vault
    static func clearCache(for vault: Vault) {
        let vaultId = String(describing: vault.id)
        cacheEntries.removeAll { $0.vaultId == vaultId }
    }
    
    /// Clears all cached timestamps
    static func clearAllCache() {
        cacheEntries.removeAll()
    }
    
    /// Checks if we recently fetched the balance (within cache validity duration)
    func shouldFetchBalance(for vault: Vault) -> Bool {
        let vaultId = String(describing: vault.id)
        guard let cacheEntry = Self.cacheEntries.first(where: { $0.vaultId == vaultId }) else { 
            return true 
        }
        return Date().timeIntervalSince(cacheEntry.lastFetchDate) >= Self.cacheValidityDuration
    }
}

private extension VultTierService {
    struct CacheEntry: Codable {
        let vaultId: String
        let lastFetchDate: Date
    }
    
    func fetchVultBalance(for vault: Vault) async -> Decimal {
        let vaultId = String(describing: vault.id)
        
        // Check if we need to fetch fresh balance
        if shouldFetchBalance(for: vault) {
            // Fetch fresh balance
            await addEthChainIfNeeded(for: vault)
            let vultToken = await getOrAddVultTokenIfNeeded(to: vault)
            if let vultToken {
                await BalanceService.shared.updateBalance(for: vultToken)
            }
            
            // Update the cache entry
            Self.cacheEntries.removeAll { $0.vaultId == vaultId }
            Self.cacheEntries.append(CacheEntry(vaultId: vaultId, lastFetchDate: Date()))
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
