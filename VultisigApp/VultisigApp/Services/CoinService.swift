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

    static func removeCoins(coins: [Coin], vault: Vault) throws {
        for coin in coins {
            let coinsToRemove = vault.coins.filter {
                $0.chain == coin.chain &&
                $0.ticker.caseInsensitiveCompare(coin.ticker) == .orderedSame &&
                $0.contractAddress.caseInsensitiveCompare(coin.contractAddress) == .orderedSame
            }

            if !coinsToRemove.isEmpty {
                for coinToRemove in coinsToRemove {
                    if let idx = vault.coins.firstIndex(of: coinToRemove) {
                         vault.coins.remove(at: idx)
                    }
                    Storage.shared.delete(coinToRemove)
                }
            }
        }
    }

    static func saveAssets(for vault: Vault, selection: Set<CoinMeta>) async {
        do {
            // Step 1: Remove coins that are no longer selected
            try removeDeselectedCoins(vault: vault, selection: selection)

            // Step 2: Add newly selected coins
            try await addNewlySelectedCoins(vault: vault, selection: selection)

        } catch {
            print("fail to save asset,\(error)")
        }
    }

    // MARK: - Main Flow Methods

    private static func removeDeselectedCoins(vault: Vault, selection: Set<CoinMeta>) throws {
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
            if !chainsBeingRemoved.contains(coin.chain) && shouldHideToken(coin) {
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
            var assetPriceProviderId = asset.priceProviderId
            if assetPriceProviderId.isEmpty {
                // When fail to match a price provider id , should not stop user from adding the coin
                do {
                    let priceProviderID  = try await CryptoPriceService.shared.resolvePriceProviderID(symbol: asset.ticker, contract: asset.contractAddress)
                    assetPriceProviderId = priceProviderID ?? ""
                } catch {
                    print("Error resolving price provider ID for \(asset.ticker): \(error.localizedDescription)")
                }
            }
            if let newCoin = try addToChain(asset: asset, to: vault, priceProviderId: assetPriceProviderId) {
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
        let pubKey = vault.chainPublicKeys.first { $0.chain == asset.chain }?.publicKeyHex
        let isDerived = pubKey != nil
        let newCoin = try CoinFactory.create(
            asset: asset,
            publicKeyECDSA: pubKey ?? vault.pubKeyECDSA,
            publicKeyEdDSA: pubKey ?? vault.pubKeyEdDSA,
            hexChainCode: vault.hexChainCode,
            isDerived: isDerived
        )

        // Check if coin with same ID already exists
        if vault.coins.contains(where: { $0.id == newCoin.id }) {
            return vault.coins.first(where: { $0.id == newCoin.id })
        }
        
        // Secondary check using vault.coin(for:) to catch duplicates with differing contract address formats or IDs
        if let existing = vault.coin(for: asset) {
            return existing
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

        return try addToChain(asset: asset, to: vault, priceProviderId: priceProviderId)
    }

    static func fetchDiscoveredTokens(nativeCoin: CoinMeta, address: String) async throws -> [CoinMeta] {
        var tokens: [CoinMeta] = []
        switch nativeCoin.chain.chainType {
        case .EVM:
            let service = try EvmService.getService(forChain: nativeCoin.chain)
            tokens = try await service.getTokens(nativeToken: nativeCoin, address: address)
        case .Solana:
            tokens = try await SolanaService.shared.fetchTokens(for: address)
        case .Sui:
            tokens = try await SuiService.shared.getAllTokensWithMetadata(address: address)
        case .THORChain:
            switch nativeCoin.chain {
            case .thorChain, .thorChainChainnet, .thorChainStagenet2:
                let service = ThorchainServiceFactory.getService(for: nativeCoin.chain)
                tokens = try await service.fetchTokens(address)
            case .mayaChain:
                tokens = try await MayachainService.shared.fetchTokens(address)
            default:
                tokens = []
            }
        default:
            tokens = []
        }

        return tokens
    }

    static func addDiscoveredTokens(nativeToken: Coin, to vault: Vault) async {
        do {
            let tokens = try await fetchDiscoveredTokens(nativeCoin: nativeToken.toCoinMeta(), address: nativeToken.address)

            for token in tokens {
                do {
                    // Skip discovered tokens that match the native token's ticker
                    // (e.g. cosmos balance API returns "rune" denom as a non-native token,
                    // but it's already tracked as the native RUNE coin)
                    if token.ticker.caseInsensitiveCompare(nativeToken.ticker) == .orderedSame {
                        continue
                    }

                    // Check if token is hidden by user
                    if isTokenHidden(token, vault: vault) {
                        continue
                    }

                    let existingCoin = vault.coin(for: token)
                    if existingCoin != nil {
                        continue
                    }

                    // Check for spam tokens
                    if await isSpamToken(token) {
                        continue
                    }

                    _ =  try addToChain(asset: token, to: vault, priceProviderId: token.priceProviderId)
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
    private static func isSpamToken(_ token: CoinMeta) async -> Bool {
        // Additional spam filtering patterns
        let suspiciousPatterns = [
            "t.me/",           // Telegram links
            "claim",           // Claim scams
            "airdrop",         // Airdrop scams
            "visit",           // Visit scams
            "*",               // Wildcards
            "|",               // Pipe characters often used in scam names
            "www",             // WWW prefix (often used in scam URLs)
            "http://",         // HTTP URLs
            "https://",        // HTTPS URLs
            ".com",            // .com domain
            ".net",            // .net domain
            ".org",            // .org domain
            ".io",             // .io domain
            ".xyz",            // .xyz domain
            ".app",            // .app domain
            ".co",             // .co domain
            ".site",           // .site domain
            ".online",         // .online domain
            ".tech",           // .tech domain
            ".dev"             // .dev domain
        ]

        let tickerLower = token.ticker.lowercased()
        let hasSpamPattern = suspiciousPatterns.contains { pattern in
            tickerLower.contains(pattern)
        }

        if hasSpamPattern {
            return true
        }

        // Check for URL-like patterns (e.g., "example.com", "subdomain.domain")
        // This catches URLs without protocol prefixes anywhere in the string
        let urlPattern = #"[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,}"#
        if let regex = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive) {
            let range = NSRange(location: 0, length: tickerLower.utf16.count)
            if regex.firstMatch(in: tickerLower, options: [], range: range) != nil {
                return true
            }
        }

        // Check for non-ASCII characters (common in scam tokens using lookalike characters)
        let asciiOnly = token.ticker.allSatisfy { $0.isASCII }
        if !asciiOnly {
            return true
        }

        // Check if logo is empty (spam tokens often have empty logos)
        if token.logo.isEmpty {
            return true
        }

        // Check if logo URL is valid (not 404 or invalid)
        if await isInvalidLogoURL(token.logo) {
            return true
        }

        return false
    }

    /// Check if a logo URL is invalid (404, unreachable, or not a valid URL)
    private static func isInvalidLogoURL(_ logo: String) async -> Bool {
        // Skip local asset names (not URLs) - these are fine
        guard logo.contains("http://") || logo.contains("https://") || logo.contains("://") else {
            return false // Not a URL, so we can't validate it - assume it's fine (local asset name)
        }

        // Validate URL format
        guard let url = URL(string: logo) else {
            return true // Invalid URL format
        }

        // Check if URL is reachable and not returning 404
        do {
            // Try HEAD first to avoid downloading the full image
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 5.0 // 5 second timeout

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return true // Invalid response
            }

            // If HEAD is not supported (405), try GET with range request
            if httpResponse.statusCode == 405 {
                var getRequest = URLRequest(url: url)
                getRequest.httpMethod = "GET"
                getRequest.setValue("bytes=0-1023", forHTTPHeaderField: "Range") // Only request first 1KB
                getRequest.timeoutInterval = 5.0

                let (_, getResponse) = try await URLSession.shared.data(for: getRequest)
                guard let httpGetResponse = getResponse as? HTTPURLResponse else {
                    return true
                }

                // Check status code from GET request
                if httpGetResponse.statusCode == 404 || httpGetResponse.statusCode >= 500 {
                    return true // Logo URL is invalid
                }

                // 200-299 and 206 (partial content) and 300-399 (redirects) are considered valid
                return false
            }

            // Consider 404 and server errors as invalid
            if httpResponse.statusCode == 404 || httpResponse.statusCode >= 500 {
                return true // Logo URL is invalid
            }

            // 200-299 and 300-399 (redirects) are considered valid
            return false

        } catch {
            // If we can't reach the URL, consider it invalid (likely spam)
            return true
        }
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
        return vault.coins.filter { coin in
            let coinMeta = coin.toCoinMeta()
            return !selection.contains(coinMeta)
        }
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
        let vaultCoinMetas = vault.coins.map { $0.toCoinMeta() }
        return selection.filter { asset in
            // Don't add coins from chains that were removed
            // Don't add coins that already exist
            !excludedChains.contains(asset.chain) && !vaultCoinMetas.contains(asset)
        }
    }

    // MARK: - Hidden Token Management

    /// Check if a token should be hidden when removed
    private static func shouldHideToken(_ coin: Coin) -> Bool {
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
            print("🙈 Hiding Token: \(coin.ticker) (\(coin.contractAddress))")
            let hiddenToken = HiddenToken(coin: coin)
            vault.hiddenTokens.append(hiddenToken)
            Storage.shared.insert([hiddenToken])
        } else {
            print("🙈 Token already hidden: \(coin.ticker)")
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
