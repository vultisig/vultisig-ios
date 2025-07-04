//
//  CoinService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 07/08/24.
//

import Foundation

@MainActor
struct CoinService {
    
    // MARK: - Core Operations
    
    /// Removes the specified coins from the vault and storage
    static func removeCoins(coins: [Coin], vault: Vault) async throws {
        print("--- REMOVE COINS: Removing \(coins.count) coins ---")
        for coin in coins {
            print("  - Attempting to remove: \(coin.ticker) on \(coin.chain.name)")
            if let idx = vault.coins.firstIndex(where: { $0.ticker == coin.ticker && $0.chain == coin.chain }) {
                vault.coins.remove(at: idx)
                print("    ✓ Removed from vault at index \(idx)")
            } else {
                print("    ✗ Not found in vault!")
            }
            
            await Storage.shared.delete(coin)
            print("    ✓ Deleted from storage")
        }
        print("--- REMOVE COINS: Complete ---")
    }
    
    /// Main entry point for saving asset selection changes
    /// - Parameters:
    ///   - vault: The vault to update
    ///   - selection: The new set of selected assets
    static func saveAssets(for vault: Vault, selection: Set<CoinMeta>) async {
        print("\n========== SAVE ASSETS START ==========")
        
        // Check for invalid vault state
        let orphanedTokens = detectOrphanedTokens(vault: vault)
        if !orphanedTokens.isEmpty {
            print("⚠️ VAULT HAS ORPHANED TOKENS (tokens without native token):")
            for (chain, tokens) in orphanedTokens {
                print("  - \(chain.name): \(tokens.map { $0.ticker }.joined(separator: ", "))")
            }
        }
        
        print("Current vault coins: \(vault.coins.count)")
        for coin in vault.coins {
            print("  - Vault has: \(coin.ticker) on \(coin.chain.name) (native: \(coin.isNativeToken))")
        }
        print("\nNew selection: \(selection.count) assets")
        for asset in selection {
            print("  - Selected: \(asset.ticker) on \(asset.chain.name) (native: \(asset.isNativeToken))")
        }
        
        do {
            // Step 1: Remove coins that are no longer selected
            try await removeDeselectedCoins(vault: vault, selection: selection)
            
            // Step 2: Add newly selected coins
            try await addNewlySelectedCoins(vault: vault, selection: selection)
            
        } catch {
            print("fail to save asset,\(error)")
        }
        
        print("\nFinal vault coins: \(vault.coins.count)")
        for coin in vault.coins {
            print("  - Final vault has: \(coin.ticker) on \(coin.chain.name)")
        }
        print("========== SAVE ASSETS END ==========\n")
    }
    
    // MARK: - Main Flow Methods
    
    private static func removeDeselectedCoins(vault: Vault, selection: Set<CoinMeta>) async throws {
        print("=== REMOVE DESELECTED COINS START ===")
        print("Vault has \(vault.coins.count) coins")
        print("Selection has \(selection.count) coins")
        
        // Find all coins that need to be removed
        let coinsToRemove = findAllCoinsToRemove(vault: vault, selection: selection)
        print("Found \(coinsToRemove.count) coins to remove")
        for coin in coinsToRemove {
            print("  - Will remove: \(coin.ticker) on \(coin.chain.name)")
        }
        
        // Check which coins should be hidden (auto-discovered tokens being removed)
        for coin in coinsToRemove {
            if shouldHideToken(coin, vault: vault) {
                await addToHiddenTokens(coin, vault: vault)
            }
        }
        
        // Remove them
        try await removeCoins(coins: coinsToRemove, vault: vault)
        print("=== REMOVE DESELECTED COINS END ===")
    }
    
    private static func addNewlySelectedCoins(vault: Vault, selection: Set<CoinMeta>) async throws {
        // Find chains where the native token is being removed from the selection
        let chainsBeingRemoved = findChainsBeingRemoved(selection: selection)
        print("--- Finding chains being removed ---")
        print("Chains being removed: \(chainsBeingRemoved.count)")
        for chain in chainsBeingRemoved {
            print("  - Chain being removed: \(chain.name)")
        }
        
        // Filter selection to exclude tokens from chains being removed
        let filteredSelection = selection.filter { asset in
            !chainsBeingRemoved.contains(asset.chain)
        }
        
        print("Filtered selection: \(filteredSelection.count) assets (was \(selection.count))")
        if selection.count != filteredSelection.count {
            print("Excluded \(selection.count - filteredSelection.count) tokens from removed chains")
        }
        
        // Find new coins to add from the filtered selection
        let newCoins = findNewCoins(
            vault: vault,
            selection: filteredSelection,
            excludedChains: Set<Chain>() // We already filtered, so no need to exclude again
        )
        
        print("New coins to add: \(newCoins.count)")
        for coin in newCoins {
            print("  - Will add: \(coin.ticker) on \(coin.chain.name) (native: \(coin.isNativeToken))")
        }
        
        // Check if any selected coins are currently hidden and unhide them
        for asset in filteredSelection {
            if isTokenHidden(asset, vault: vault) {
                await unhideToken(asset, vault: vault)
            }
        }
        
        // Add them with auto-discovery for native tokens
        try await addToChain(assets: newCoins, to: vault)
    }
    
    private static func findAllCoinsToRemove(vault: Vault, selection: Set<CoinMeta>) -> [Coin] {
        print("--- Finding all coins to remove ---")
        
        // Find directly deselected coins
        let directlyRemovedCoins = findRemovedCoins(vault: vault, selection: selection)
        print("Directly removed coins: \(directlyRemovedCoins.count)")
        for coin in directlyRemovedCoins {
            print("  - Direct remove: \(coin.ticker) on \(coin.chain.name)")
        }
        
        // Find chains where native token was removed
        let chainsWithRemovedNative = findChainsWithRemovedNativeToken(vault: vault, selection: selection)
        print("Chains with removed native token: \(chainsWithRemovedNative.count)")
        for chain in chainsWithRemovedNative {
            print("  - Chain to remove entirely: \(chain.name)")
        }
        
        // Find all coins from chains where native was removed
        let coinsFromRemovedChains = vault.coins.filter { coin in
            chainsWithRemovedNative.contains(coin.chain)
        }
        print("Coins from removed chains: \(coinsFromRemovedChains.count)")
        for coin in coinsFromRemovedChains {
            print("  - From removed chain: \(coin.ticker) on \(coin.chain.name)")
        }
        
        // Combine and deduplicate
        let allToRemove = Array(Set(directlyRemovedCoins + coinsFromRemovedChains))
        print("Total coins to remove after deduplication: \(allToRemove.count)")
        return allToRemove
    }
    
    static func addToChain(assets: [CoinMeta], to vault: Vault) async throws {
        for asset in assets {
            if let newCoin = try await addToChain(asset: asset, to: vault, priceProviderId: asset.priceProviderId) {
                // Only do auto-discovery for native tokens
                if newCoin.isNativeToken {
                    print("Add discovered tokens for \(asset.ticker) on the chain \(asset.chain.name)")
                    await addDiscoveredTokens(nativeToken: newCoin, to: vault)
                }
            }
        }
    }
    
    static func addToChain(asset: CoinMeta, to vault: Vault, priceProviderId: String?) async throws -> Coin? {
        let newCoin = try CoinFactory.create(asset: asset, vault: vault)
        if let priceProviderId {
            newCoin.priceProviderId = priceProviderId
        }
        // Save the new coin first
        // On IOS / IpadOS 18 , we have to user insert to insert the newCoin into modelcontext
        // otherwise it report an error "Illegal attempt to map a relationship containing temporary objects to its identifiers."
        await Storage.shared.insert([newCoin])
        try await Storage.shared.save()
        vault.coins.append(newCoin)
        return newCoin
    }
    
    static func addDiscoveredTokens(nativeToken: Coin, to vault: Vault) async {
        do {
            var tokens: [CoinMeta] = []
            print("🔍 Auto-discovery starting for \(nativeToken.ticker) on \(nativeToken.chain.name)")
            switch nativeToken.chain.chainType {
            case .EVM :
                print("  - Chain type: EVM")
                let service = try EvmServiceFactory.getService(forChain: nativeToken.chain)
                print("  - Got EVM service: \(type(of: service))")
                tokens = await service.getTokens(nativeToken: nativeToken)
                print("  - Raw tokens from service: \(tokens.count)")
                // Filter out spam tokens by checking for valid price provider ID
                let beforeFilter = tokens.count
                tokens = tokens.filter { !$0.priceProviderId.isEmpty }
                print("  - Filtered out \(beforeFilter - tokens.count) tokens without priceProviderId")
            case .Solana:
                print("  - Chain type: Solana")
                tokens = try await SolanaService.shared.fetchTokens(for: nativeToken.address)
                print("  - Raw tokens from service: \(tokens.count)")
                // Filter out spam tokens by checking for valid price provider ID
                let beforeFilter = tokens.count
                tokens = tokens.filter { !$0.priceProviderId.isEmpty }
                print("  - Filtered out \(beforeFilter - tokens.count) tokens without priceProviderId")
            case .Sui:
                print("  - Chain type: Sui")
                tokens = try await SuiService.shared.getAllTokensWithMetadata(coin: nativeToken)
                print("  - Raw tokens from service: \(tokens.count)")
            case .THORChain:
                print("  - Chain type: THORChain")
                tokens = try await ThorchainService.shared.fetchTokens(nativeToken.address)
                print("  - Raw tokens from service: \(tokens.count)")
            default:
                print("  - Chain type: \(nativeToken.chain.chainType) - no auto-discovery")
                tokens = []
            }
            
            print("Auto-discovery found \(tokens.count) tokens for \(nativeToken.ticker) on \(nativeToken.chain.name)")
            
            var addedCount = 0
            var skippedHiddenCount = 0
            var skippedExistingCount = 0
            
            for token in tokens {
                do {
                    // Check if token is hidden by user
                    if isTokenHidden(token, vault: vault) {
                        print("  ⛔ Skipping hidden token: \(token.ticker) on \(token.chain.name)")
                        skippedHiddenCount += 1
                        continue
                    }
                    
                    let existingCoin =  vault.coin(for: token)
                    if existingCoin != nil {
                        skippedExistingCount += 1
                        continue
                    }
                    
                    _ = try await addToChain(asset: token, to: vault, priceProviderId: nil)
                    print("  ✅ Added token: \(token.ticker) on \(token.chain.name)")
                    addedCount += 1
                } catch {
                    print("  ❌ Error adding token \(token.ticker): \(error.localizedDescription)")
                }
            }
            
            print("Auto-discovery summary: Found \(tokens.count), Added \(addedCount), Skipped hidden \(skippedHiddenCount), Skipped existing \(skippedExistingCount)")
        } catch {
            print("❌ Error in auto-discovery: \(error)")
            print("   Error type: \(type(of: error))")
            print("   Error details: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helper Functions
    
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
        print("--- Finding removed coins ---")
        let removed = vault.coins.filter { coin in
            let isInSelection = selection.contains(where: { meta in
                let matches = meta.chain == coin.chain && meta.ticker == coin.ticker
                if matches {
                    print("  - Found match for \(coin.ticker) on \(coin.chain.name)")
                }
                return matches
            })
            if !isInSelection {
                print("  - Coin NOT in selection: \(coin.ticker) on \(coin.chain.name)")
            }
            return !isInSelection
        }
        print("Total removed coins: \(removed.count)")
        return removed
    }
    
    private static func findChainsWithRemovedNativeToken(vault: Vault, selection: Set<CoinMeta>) -> Set<Chain> {
        print("--- Finding chains with removed native tokens ---")
        
        // First, let's see what native tokens are in the vault
        let nativeTokensInVault = vault.coins.filter { $0.isNativeToken }
        print("Native tokens in vault: \(nativeTokensInVault.count)")
        for token in nativeTokensInVault {
            print("  - Vault has native: \(token.ticker) on \(token.chain.name)")
        }
        
        // Now check what native tokens are in selection
        let nativeTokensInSelection = selection.filter { $0.isNativeToken }
        print("Native tokens in selection: \(nativeTokensInSelection.count)")
        for token in nativeTokensInSelection {
            print("  - Selection has native: \(token.ticker) on \(token.chain.name)")
        }
        
        let removedNativeTokens = vault.coins.filter { coin in
            // Only check native tokens
            guard coin.isNativeToken else { return false }
            
            // Check if this native token's chain is still selected
            let chainStillHasNativeToken = selection.contains(where: { meta in
                meta.chain == coin.chain && meta.isNativeToken
            })
            
            if !chainStillHasNativeToken {
                print("  - Native token \(coin.ticker) on \(coin.chain.name) is being removed (chain has no native token in selection)")
            }
            
            return !chainStillHasNativeToken
        }
        
        print("Removed native tokens: \(removedNativeTokens.count)")
        for token in removedNativeTokens {
            print("  - Native token removed: \(token.ticker) on \(token.chain.name)")
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
    private static func addToHiddenTokens(_ coin: Coin, vault: Vault) async {
        // Check if already hidden
        let alreadyHidden = vault.hiddenTokens.contains { hidden in
            hidden.coinMeta == coin.toCoinMeta()
        }
        
        if !alreadyHidden {
            let hiddenToken = HiddenToken(coin: coin)
            vault.hiddenTokens.append(hiddenToken)
            await Storage.shared.insert([hiddenToken])
            print("Added to hidden tokens: \(coin.ticker) on \(coin.chain.name)")
        }
    }
    
    /// Check if a token is in the hidden list
    private static func isTokenHidden(_ token: CoinMeta, vault: Vault) -> Bool {
        return vault.hiddenTokens.contains { hidden in
            hidden.coinMeta == token
        }
    }
    
    /// Remove a token from the hidden list (when user re-selects it)
    static func unhideToken(_ token: CoinMeta, vault: Vault) async {
        if let index = vault.hiddenTokens.firstIndex(where: { hidden in
            hidden.coinMeta == token
        }) {
            let hiddenToken = vault.hiddenTokens[index]
            vault.hiddenTokens.remove(at: index)
            await Storage.shared.delete(hiddenToken)
            print("Removed from hidden tokens: \(token.ticker) on \(token.chain.name)")
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
                print("⚠️ WARNING: Chain \(chain.name) has \(coins.count) tokens but NO native token!")
                orphanedTokens[chain] = coins
            }
        }
        
        return orphanedTokens
    }
    
}
