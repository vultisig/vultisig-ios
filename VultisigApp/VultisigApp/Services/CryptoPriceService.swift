import Foundation
import SwiftUI
import Combine

public class CryptoPriceService: ObservableObject {
    
    struct ResolvedSources {
        let providerIds: [String]
        let contracts: [Chain: [String]]
    }
    
    public static let shared = CryptoPriceService()
    
    // Track when prices were last updated to avoid redundant API calls
    private var lastPriceUpdate: [String: Date] = [:]
    
    // Time interval for refreshing prices (5 minutes)
    private let priceRefreshInterval: TimeInterval = 5 * 60
    
    // Flag to track ongoing fetch operations
    private var isFetchingPrices = false
    private var lastFetchTime: Date?
    
    // Minimum time between price fetches to prevent rapid successive calls
    private let minFetchInterval: TimeInterval = 2.0 // 2 seconds
    
    private init() {
        // Load any cached price update timestamps
        if let savedTimestamps = UserDefaults.standard.dictionary(forKey: "CryptoPriceUpdateTimes") as? [String: Date] {
            self.lastPriceUpdate = savedTimestamps
        }
    }
    
    private func canFetchPrices() -> Bool {
        // Prevent multiple simultaneous fetches
        if isFetchingPrices {
            // Price fetch already in progress
            return false
        }
        
        // Debounce frequent calls
        if let lastFetch = lastFetchTime, Date().timeIntervalSince(lastFetch) < minFetchInterval {
            // Throttling price fetch to avoid excessive API calls
            return false
        }
        
        return true
    }
    
    /// Check if a coin needs a price update
    private func needsPriceUpdate(coin: Coin) -> Bool {
        let coinId = coin.ticker + "_" + coin.chain.rawValue
        
        // If we have a recent price, check if it's still fresh
        if let lastUpdate = lastPriceUpdate[coinId] {
            return Date().timeIntervalSince(lastUpdate) > priceRefreshInterval
        }
        
        // Otherwise, we need to update
        return true
    }
    
    func fetchPrices(vault: Vault) async throws {
        // Check if we can fetch prices (debounce/throttle)
        guard canFetchPrices() else {
            // Still refresh the UI with existing rates
            await refresh(vault: vault)
            await refresh(coins: vault.coins)
            return
        }
        
        try await fetchPrices(coins: vault.coins)
        await refresh(vault: vault)
        await refresh(coins: vault.coins)
    }
    
    func fetchPrice(coin: Coin) async throws {
        // Check if we can fetch prices (debounce/throttle)
        guard canFetchPrices() else {
            // Still refresh the UI with existing rates
            await refresh(coins: [coin])
            return
        }
        
        try await fetchPrices(coins: [coin])
        await refresh(coins: [coin])
    }
}

private extension CryptoPriceService {
    
    // Handle THORChain assets price fetching from pools endpoint
    func fetchThorchainAssetPrice(coins: [Coin]) async throws {
        var rates: [Rate] = []
        let thorchainService = ThorchainService.shared
        // Processing THORChain assets for pricing
        
        for coin in coins {
            // Format the asset name using the helper
            let assetName = thorchainService.formatAssetName(chain: coin.chain, symbol: coin.ticker)
            
            // Get the crypto ID for storing rates
            let cryptoId = RateProvider.cryptoId(for: coin).id
            
            // Get the price from THORChain
            let assetPrice = await thorchainService.getAssetPriceInUSD(assetName: assetName)
            // Fetched USD price for asset
            
            // If we have a valid USD price, create rates for all supported fiat currencies
            if assetPrice > 0 {
                // Create rate for USD (direct from THORChain)
                let usdRate = Rate(fiat: "usd", crypto: cryptoId, value: assetPrice)
                rates.append(usdRate)
                // Added USD rate for asset
                
                // Create rates for other fiat currencies using exchange rates
                for currency in SettingsCurrency.allCases {
                    let fiat = currency.rawValue.lowercased()
                    
                    // Skip USD as we already added it
                    if fiat == "usd" { continue }
                    
                    // Convert USD price to target fiat using our exchange rate table
                    if let convertedValue = FiatExchangeRates.shared.convert(amount: assetPrice, fromUSD: fiat) {
                        let rate = Rate(fiat: fiat, crypto: cryptoId, value: convertedValue)
                        rates.append(rate)
                        // Converted price to target fiat
                    } else {
                        // Failed to convert price to target fiat
                    }
                }
            } else {
                // Invalid or zero price fetched
            }
        }
        
        // Save all rates to the provider
        try await RateProvider.shared.save(rates: rates)
        // Saved rates for THORChain assets
    }
    
    @MainActor func refresh(vault: Vault) {
        vault.objectWillChange.send()
    }
    
    @MainActor func refresh(coins: [Coin]) {
        for coin in coins {
            coin.objectWillChange.send()
        }
    }
    
    func fetchPrices(coins: [Coin]) async throws {
        // Set fetching flag to prevent concurrent calls
        guard !isFetchingPrices else {
            // Price fetch already in progress
            return
        }
        
        isFetchingPrices = true
        defer {
            isFetchingPrices = false
            lastFetchTime = Date()
        }
        
        // First, ensure we have up-to-date fiat exchange rates
        if FiatExchangeRates.shared.needsUpdate {
            _ = await FiatExchangeRates.shared.updateExchangeRates()
        }
        
        // Filter out coins that already have recent prices
        let coinsNeedingUpdate = coins.filter { needsPriceUpdate(coin: $0) }
        
        if coinsNeedingUpdate.isEmpty {
            // No coins need updates at this time
            // Ensure UI is refreshed even if we're using cached prices
            await refresh(coins: coins)
            return
        }
        
        // Fetching prices for coins that need updates
        
        // Step 1: Try to get asset prices from normal price sources first
        
        // Resolve all coins to their price sources
        let sources = resolveSources(coins: coinsNeedingUpdate)
        
        // Try to fetch prices from normal sources
        if !sources.providerIds.isEmpty {
            do {
                try await fetchPrices(ids: sources.providerIds, coins: coinsNeedingUpdate)
            } catch {
                // Error fetching provider prices, continuing with other sources
            }
        }
        
        if !sources.contracts.isEmpty {
            for (chain, contracts) in sources.contracts {
                do {
                    try await fetchPrices(contracts: contracts, chain: chain)
                } catch {
                    // Error fetching contract prices, continuing with other sources
                }
            }
        }
        
        // Step 2: For THORChain assets without prices, try THORChain pools
        
        // Find all THORChain assets without prices after normal sources that still need updates
        let thorchainCoinsWithoutPrices = coinsNeedingUpdate.filter { coin in
            // Check if this coin is on THORChain
            guard coin.chain == .thorChain else { return false }
            
            // Special case for TCY - always use THORChain pricing
            if coin.ticker == "TCY" {
                // Only print this once per fetch
                // Always include TCY for THORChain pricing
                return true
            }
            
            // Check if it already has a price from normal sources
            let hasPrice = RateProvider.shared.rate(for: coin) != nil
            return !hasPrice
        }
        
        // Only log if we actually have coins to process
        if !thorchainCoinsWithoutPrices.isEmpty {
            // Processing THORChain coins without prices
            
            // Try to fetch THORChain asset prices, but don't fail if there's an error
            do {
                try await fetchThorchainAssetPrice(coins: thorchainCoinsWithoutPrices)
            } catch {
                // Error fetching THORChain prices
            }
        }
        
        // Update the last fetched time for all coins we've processed
        for coin in coinsNeedingUpdate {
            let coinId = coin.ticker + "_" + coin.chain.rawValue
            lastPriceUpdate[coinId] = Date()
        }
        
        // Save our updated timestamps
        UserDefaults.standard.set(lastPriceUpdate, forKey: "CryptoPriceUpdateTimes")
        
        // Step 3: If still no price, it will default to $0.0 (handled in RateProvider)
    }
    
    func resolveSources(coins: [Coin]) -> ResolvedSources {
        var providerIds: [String] = []
        var contracts: [Chain: [String]] = [:]
        
        for coin in coins {
            switch RateProvider.cryptoId(for: coin) {
            case .priceProvider(let id):
                providerIds.append(id)
            case .contract(let id):
                contracts[coin.chain, default: []].append(id)
            }
        }
        
        return ResolvedSources(providerIds: providerIds, contracts: contracts)
    }
    
    func fetchPrices(ids: [String], coins: [Coin]) async throws {
        let idString = ids.joined(separator: ",")
        let endpoint = Endpoint.fetchCryptoPrices(ids: idString, currencies: "usd")
        
        let (data, _) = try await URLSession.shared.data(from: endpoint)
        let response = try JSONDecoder().decode([String: [String: Double]].self, from: data)
        
        var rates: [Rate] = []
        
        for (id, coin) in zip(ids, coins) {
            if let priceData = response[id],
               let price = priceData["usd"] {
                let rate = Rate(fiat: "usd", crypto: id, value: price)
                rates.append(rate)
                // Fetched price from normal source
                
                // Convert to other fiat currencies if we have exchange rates
                for currency in SettingsCurrency.allCases {
                    let fiat = currency.rawValue.lowercased()
                    if fiat != "usd",
                       let convertedValue = FiatExchangeRates.shared.convert(amount: price, fromUSD: fiat) {
                        let convertedRate = Rate(fiat: fiat, crypto: id, value: convertedValue)
                        rates.append(convertedRate)
                        // Converted price to target fiat
                    }
                }
            } else {
                // No price fetched from normal source
            }
        }
        
        try await RateProvider.shared.save(rates: rates)
    }
    
    func fetchPrices(contracts: [String], chain: Chain) async throws {
        
        if chain == .solana {
            
            var rates: [Rate] = []
            for contract in contracts {
                let poolPrice = await SolanaService.getTokenUSDValue(contractAddress: contract)
                let poolRate: Rate = .init(fiat: "usd", crypto: contract, value: poolPrice)
                rates.append(poolRate)
            }
            
            try await RateProvider.shared.save(rates: rates)

            
        } else if chain == .sui {
            
            var rates: [Rate] = []
            for contract in contracts {
                let poolPrice = await SuiService.getTokenUSDValue(contractAddress: contract)
                let poolRate: Rate = .init(fiat: "usd", crypto: contract, value: poolPrice)
                rates.append(poolRate)
            }
            
            try await RateProvider.shared.save(rates: rates)
            
        } else {
            
            let currencies = SettingsCurrency.allCases
                .map { $0.rawValue }
                .joined(separator: ",")
            
            let url = Endpoint.fetchTokenPrice(
                network: coinGeckoPlatform(chain: chain),
                addresses: contracts,
                currencies: currencies
            )
            
            let (data, _) = try await URLSession.shared.data(from: url)
            
            let response = try JSONDecoder().decode([String: [String: Double]].self, from: data)
            
            
            let contractsNotFoundOnCoingecko = contracts.filter{ !response.keys.contains($0) }
            
            var rates = mapRates(response: response)
            
            // now lets try to find the price for the notFoundPricesOnCoingecko
            for contract in contractsNotFoundOnCoingecko {
                let lifiRate = try await fetchLifiTokenPrice(contract: contract, chain: chain)
                rates.append(lifiRate)
            }
            
            try await RateProvider.shared.save(rates: rates)
        }
    }
    
    func fetchLifiTokenPrice(contract: String, chain: Chain) async throws -> Rate {
        let url = Endpoint.fetchLifiTokenPrice(
            network: chain.ticker,
            address: contract
        )
        
        let (data, _) = try await URLSession.shared.data(from: url)
        if let priceUsd = Utils.extractResultFromJson(fromData: data, path: "priceUSD") as? String {
            let price = Double(priceUsd) ?? 0.0
            let rate: Rate = .init(fiat: "usd", crypto: contract, value: price)
            return rate
        }
        
        return .init(fiat: "usd", crypto: contract, value: 0.0)
    }
    
    func mapRates(response: [String: [String: Double]]) -> [Rate] {
        let rates: [[Rate]] = response.map { crypto, map in
            return SettingsCurrency.allCases.compactMap { currency in
                let fiat = currency.rawValue.lowercased()
                guard let value = map[fiat] else { return nil }
                return Rate(fiat: fiat, crypto: crypto, value: value)
            }
        }
        
        return Array(rates.joined())
    }
    
    private func coinGeckoPlatform(chain: Chain) -> String {
        switch chain {
        case .ethereum:
            return "ethereum"
        case .avalanche:
            return "avalanche"
        case .base:
            return "base"
        case .blast:
            return "blast"
        case .arbitrum:
            return "arbitrum-one"
        case .polygon, .polygonV2:
            return "polygon-pos"
        case .optimism:
            return "optimistic-ethereum"
        case .bscChain:
            return "binance-smart-chain"
        case .zksync:
            return "zksync"
        case .thorChain, .solana, .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash, .gaiaChain, .kujira, .mayaChain, .cronosChain, .polkadot, .dydx, .sui, .ton, .osmosis, .terra, .terraClassic, .noble, .ripple, .akash, .tron:
            return .empty
        }
    }
}
