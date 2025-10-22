//
//  CoinService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 07/08/24.
//

import Foundation
import SwiftData

@MainActor
struct CoinService {
    
    static func removeCoins(coins: [Coin], vault: Vault)  throws {
        for coin in coins {
            if let idx = vault.coins.firstIndex(where: { $0.ticker == coin.ticker && $0.chain == coin.chain }) {
                vault.coins.remove(at: idx)
            }
            Storage.shared.delete(coin)
        }
    }
    
    static func saveAssets(for vault: Vault, selection: Set<CoinMeta>) async {
        do {
            // Step 1: Remove coins that are no longer selected
            try await removeDeselectedCoins(vault: vault, selection: selection)
            
            // Step 2: Add newly selected coins
            try await addNewlySelectedCoins(vault: vault, selection: selection)
            
        } catch {
            print("fail to save asset,\(error)")
        }
    }
    
    // MARK: - Main Flow Methods
    
    private static func removeDeselectedCoins(vault: Vault, selection: Set<CoinMeta>) async throws {
        // Find all coins that need to be removed
        let coinsToRemove = findAllCoinsToRemove(vault: vault, selection: selection)
        
        // Find chains where native token was removed (entire chain being removed)
        let chainsBeingRemoved = findChainsWithRemovedNativeToken(vault: vault, selection: selection)
        
        // Clear hidden tokens for chains being removed entirely
        for chain in chainsBeingRemoved {
            clearHiddenTokensForChain(chain, vault: vault)
        }
        
        // Check which remaining coins should be hidden (auto-discovered tokens being removed individually)
        for coin in coinsToRemove {
            // Only hide if the chain is NOT being removed entirely
            if !chainsBeingRemoved.contains(coin.chain) && shouldHideToken(coin, vault: vault) {
                addToHiddenTokens(coin, vault: vault)
            }
        }
        
        // Remove them
        try removeCoins(coins: coinsToRemove, vault: vault)
        vault.defiChains.removeAll { chainsBeingRemoved.contains($0) }
    }
    
    static func addNewlySelectedCoins(vault: Vault, selection: Set<CoinMeta>) async throws {
        // Find chains where the native token is being removed from the selection
        let chainsBeingRemoved = findChainsBeingRemoved(selection: selection)
        
        // Filter selection to exclude tokens from chains being removed
        let filteredSelection = selection.filter { asset in
            !chainsBeingRemoved.contains(asset.chain)
        }
        
        // Find new coins to add from the filtered selection
        let newCoins = findNewCoins(
            vault: vault,
            selection: filteredSelection,
            excludedChains: Set<Chain>() // We already filtered, so no need to exclude again
        )
        
        // Check if any selected coins are currently hidden and unhide them
        for asset in filteredSelection {
            if isTokenHidden(asset, vault: vault) {
                unhideToken(asset, vault: vault)
            }
        }
        
        // Add them with auto-discovery for native tokens
        try await addToChain(assets: newCoins, to: vault)
        vault.defiChains.append(contentsOf: Array(Set(newCoins.map(\.chain))))
    }
    
    private static func findAllCoinsToRemove(vault: Vault, selection: Set<CoinMeta>) -> [Coin] {
        // Find directly deselected coins
        let directlyRemovedCoins = findRemovedCoins(vault: vault, selection: selection)
        
        // Find chains where native token was removed
        let chainsWithRemovedNative = findChainsWithRemovedNativeToken(vault: vault, selection: selection)
        
        // Find all coins from chains where native was removed
        let coinsFromRemovedChains = vault.coins.filter { coin in
            chainsWithRemovedNative.contains(coin.chain)
        }
        
        // Combine and deduplicate
        let allToRemove = Array(Set(directlyRemovedCoins + coinsFromRemovedChains))
        return allToRemove
    }
    
    static func addToChain(assets: [CoinMeta], to vault: Vault) async throws {
        for asset in assets {
            if let newCoin = try addToChain(asset: asset, to: vault, priceProviderId: asset.priceProviderId) {
                // Only do auto-discovery for native tokens
                if newCoin.isNativeToken {
                    // Clear hidden tokens for this chain when adding native token back
                    clearHiddenTokensForChain(asset.chain, vault: vault)
                    
                    await addDiscoveredTokens(nativeToken: newCoin, to: vault)
                }
            }
        }
    }
    
    static func addToChain(asset: CoinMeta, to vault: Vault, priceProviderId: String?) throws -> Coin? {
        let newCoin = try CoinFactory.create(asset: asset,
                                             publicKeyECDSA: vault.pubKeyECDSA,
                                             publicKeyEdDSA: vault.pubKeyEdDSA,
                                             hexChainCode: vault.hexChainCode)
        
        // Check if coin with same ID already exists
        if vault.coins.contains(where: { $0.id == newCoin.id }) {
            return vault.coins.first(where: { $0.id == newCoin.id })
        }
        
        if let priceProviderId {
            newCoin.priceProviderId = priceProviderId
        }
        // Save the new coin first
        // On IOS / IpadOS 18 , we have to user insert to insert the newCoin into modelcontext
        // otherwise it report an error "Illegal attempt to map a relationship containing temporary objects to its identifiers."
        Storage.shared.insert([newCoin])
        try Storage.shared.save()
        vault.coins.append(newCoin)
        return newCoin
    }
    
    static func addIfNeeded(asset: CoinMeta, to vault: Vault, priceProviderId: String?) throws -> Coin? {
        if let coin = vault.coin(for: asset) {
            return coin
        }
        
        return try  addToChain(asset: asset, to: vault, priceProviderId: priceProviderId)
    }
    
    static func addDiscoveredTokens(nativeToken: Coin, to vault: Vault) async {
        do {
            var tokens: [CoinMeta] = []
            switch nativeToken.chain.chainType {
            case .EVM :
                let service = try EvmServiceFactory.getService(forChain: nativeToken.chain)
                tokens = await service.getTokens(nativeToken: nativeToken)
            case .Solana:
                tokens = try await SolanaService.shared.fetchTokens(for: nativeToken.address)
                // Filter out spam tokens by checking for valid price provider ID
                tokens = tokens.filter { !$0.priceProviderId.isEmpty }
            case .Sui:
                tokens = try await SuiService.shared.getAllTokensWithMetadata(coin: nativeToken)
            case .THORChain:
                let service = ThorchainServiceFactory.getService(for: nativeToken.chain)
                tokens = try await service.fetchTokens(nativeToken.address)
            default:
                tokens = []
            }
            
            for token in tokens {
                do {
                    // Check if token is hidden by user
                    if isTokenHidden(token, vault: vault) {
                        continue
                    }
                    
                    let existingCoin =  vault.coin(for: token)
                    if existingCoin != nil {
                        continue
                    }
                    
                    // If the token doesn't have a priceProviderId, try to find it in TokensStore
                    var enrichedToken = token
                    if token.priceProviderId.isEmpty {
                        if let storeToken = TokensStore.TokenSelectionAssets.first(where: { storeAsset in
                            storeAsset.chain == token.chain &&
                            storeAsset.ticker == token.ticker &&
                            storeAsset.contractAddress.lowercased() == token.contractAddress.lowercased()
                        }) {
                            enrichedToken.priceProviderId = storeToken.priceProviderId
                            enrichedToken.logo = storeToken.logo // Also use the logo from store
                        }
                    }
                    
                    // Skip tokens that still don't have priceProviderId after enrichment (likely spam)
                    if enrichedToken.priceProviderId.isEmpty && enrichedToken.chain != .thorChain && enrichedToken.chain != .thorChainStagenet {
                        continue
                    }
                    
                    // Check for spam tokens
                    if isSpamToken(enrichedToken) {
                        continue
                    }
                    
                    _ = try addToChain(asset: enrichedToken, to: vault, priceProviderId: enrichedToken.priceProviderId)
                } catch {
                    print("Error adding the token \(token.ticker) service: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Error fetching service: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helper Functions
    
    /// Check if a token appears to be spam based on its name and characteristics
    private static func isSpamToken(_ token: CoinMeta) -> Bool {
        // Additional spam filtering patterns
        let suspiciousPatterns = [
            "t.me/",           // Telegram links
            "claim",           // Claim scams
            "airdrop",         // Airdrop scams
            "visit",           // Visit scams
            "*",               // Wildcards
            "|"                // Pipe characters often used in scam names
        ]
        
        let tickerLower = token.ticker.lowercased()
        let hasSpamPattern = suspiciousPatterns.contains { pattern in
            tickerLower.contains(pattern)
        }
        
        if hasSpamPattern {
            return true
        }
        
        // Check for non-ASCII characters (common in scam tokens using lookalike characters)
        let asciiOnly = token.ticker.allSatisfy { $0.isASCII }
        if !asciiOnly {
            return true
        }
        
        return false
    }
    
    private static func findChainsBeingRemoved(selection: Set<CoinMeta>) -> Set<Chain> {
        // Get all unique chains from the selection
        let allChains = Set(selection.map { $0.chain })
        
        // Find chains that don't have their native token in the selection
        let chainsWithoutNative = allChains.filter { chain in
            !selection.contains(where: { asset in
                asset.chain == chain && asset.isNativeToken
            })
        }
        
        return chainsWithoutNative
    }
    
    private static func findRemovedCoins(vault: Vault, selection: Set<CoinMeta>) -> [Coin] {
        let removed = vault.coins.filter { coin in
            let isInSelection = selection.contains(where: { meta in
                meta.chain == coin.chain && meta.ticker == coin.ticker
            })
            return !isInSelection
        }
        return removed
    }
    
    private static func findChainsWithRemovedNativeToken(vault: Vault, selection: Set<CoinMeta>) -> Set<Chain> {
        let removedNativeTokens = vault.coins.filter { coin in
            // Only check native tokens
            guard coin.isNativeToken else { return false }
            
            // Check if this native token's chain is still selected
            let chainStillHasNativeToken = selection.contains(where: { meta in
                meta.chain == coin.chain && meta.isNativeToken
            })
            
            return !chainStillHasNativeToken
        }
        
        return Set(removedNativeTokens.map { $0.chain })
    }
    
    private static func findNewCoins(vault: Vault, selection: Set<CoinMeta>, excludedChains: Set<Chain>) -> [CoinMeta] {
        return selection.filter { asset in
            // Don't add coins from chains that were removed
            !excludedChains.contains(asset.chain) &&
            // Don't add coins that already exist
            !vault.coins.contains(where: { coin in
                coin.chain == asset.chain && coin.ticker == asset.ticker
            })
        }
    }
    
    // MARK: - Hidden Token Management
    
    /// Check if a token should be hidden when removed
    private static func shouldHideToken(_ coin: Coin, vault: Vault) -> Bool {
        // Hide token if:
        // 1. It's not a native token
        // 2. It was auto-discovered (has or had a balance)
        // 3. User is explicitly removing it
        return !coin.isNativeToken
    }
    
    /// Add a coin to the hidden tokens list
    private static func addToHiddenTokens(_ coin: Coin, vault: Vault) {
        // Check if already hidden
        let alreadyHidden = vault.hiddenTokens.contains { hidden in
            hidden.chain == coin.chain.rawValue &&
            hidden.ticker == coin.ticker &&
            hidden.contractAddress == coin.contractAddress
        }
        
        if !alreadyHidden {
            let hiddenToken = HiddenToken(coin: coin)
            vault.hiddenTokens.append(hiddenToken)
            Storage.shared.insert([hiddenToken])
        }
    }
    
    /// Check if a token is in the hidden list
    private static func isTokenHidden(_ token: CoinMeta, vault: Vault) -> Bool {
        return vault.hiddenTokens.contains { hidden in
            hidden.matches(token)
        }
    }
    
    /// Remove a token from the hidden list (when user re-selects it)
    static func unhideToken(_ token: CoinMeta, vault: Vault) {
        if let index = vault.hiddenTokens.firstIndex(where: { hidden in
            hidden.matches(token)
        }) {
            let hiddenToken = vault.hiddenTokens[index]
            vault.hiddenTokens.remove(at: index)
            Storage.shared.delete(hiddenToken)
        }
    }
    
    // MARK: - Diagnostic Functions
    
    /// Check if vault is in an invalid state (has tokens without native token)
    static func detectOrphanedTokens(vault: Vault) -> [Chain: [Coin]] {
        var orphanedTokens: [Chain: [Coin]] = [:]
        
        // Group coins by chain
        let coinsByChain = Dictionary(grouping: vault.coins) { $0.chain }
        
        // Check each chain
        for (chain, coins) in coinsByChain {
            let hasNativeToken = coins.contains { $0.isNativeToken }
            if !hasNativeToken && !coins.isEmpty {
                orphanedTokens[chain] = coins
            }
        }
        
        return orphanedTokens
    }
    
    /// Clear all hidden tokens for a specific chain
    static func clearHiddenTokensForChain(_ chain: Chain, vault: Vault) {
        // Find all hidden tokens for this chain
        let hiddenTokensToRemove = vault.hiddenTokens.filter { hidden in
            hidden.chain == chain.rawValue
        }
        
        // Remove them from the vault and storage
        for hiddenToken in hiddenTokensToRemove {
            if let index = vault.hiddenTokens.firstIndex(of: hiddenToken) {
                vault.hiddenTokens.remove(at: index)
                Storage.shared.delete(hiddenToken)
            }
        }
    }
    
}
