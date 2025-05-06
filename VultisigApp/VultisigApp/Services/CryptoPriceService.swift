import Foundation
import SwiftUI

public class CryptoPriceService: ObservableObject {
    
    struct ResolvedSources {
        let providerIds: [String]
        let contracts: [Chain: [String]]
    }
    
    public static let shared = CryptoPriceService()
    
    private init() {}
    
    func fetchPrices(vault: Vault) async throws {
        try await fetchPrices(coins: vault.coins)
        await refresh(vault: vault)
        await refresh(coins: vault.coins)
    }
    
    func fetchPrice(coin: Coin) async throws {
        try await fetchPrices(coins: [coin])
        
        await refresh(coins: [coin])
    }
}

private extension CryptoPriceService {
    
    // Handle THORChain assets price fetching from pools endpoint
    func fetchThorchainAssetPrice(coins: [Coin]) async throws {
        var rates: [Rate] = []
        let thorchainService = ThorchainService.shared
        
        for coin in coins {
            // Get the asset name for the coin
            let assetName: String
            let cryptoId: String
            
            if coin.isTCY {
                // Special case for TCY
                assetName = "THOR.TCY"
                cryptoId = "tcy"
            } else {
                // For other assets, use the formatAssetName helper
                assetName = thorchainService.formatAssetName(chain: coin.chain, symbol: coin.ticker)
                
                // Use consistent cryptoId format for RateProvider
                cryptoId = RateProvider.cryptoId(for: coin).id
            }
            
            // Get the price from THORChain
            let assetPrice = await thorchainService.getAssetPriceInUSD(assetName: assetName)
            
            // If we got a valid price (non-zero), create rates for all currencies
            if assetPrice > 0 {
                // Create rate for each currency
                for currency in SettingsCurrency.allCases {
                    let fiat = currency.rawValue.lowercased()
                    // Currently only USD is supported directly, other currencies would require conversion
                    let value = fiat == "usd" ? assetPrice : 0.0
                    
                    let rate = Rate(fiat: fiat, crypto: cryptoId, value: value)
                    rates.append(rate)
                }
            }
        }
        
        if !rates.isEmpty {
            try await RateProvider.shared.save(rates: rates)
        }
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
        // Step 1: Try to get ALL asset prices from normal price sources first
        
        // Resolve all coins to their price sources
        let sources = resolveSources(coins: coins)
        
        // Try to fetch prices from normal sources
        if !sources.providerIds.isEmpty {
            try await fetchPrices(ids: sources.providerIds)
        }
        
        if !sources.contracts.isEmpty {
            for (chain, contracts) in sources.contracts {
                try await fetchPrices(contracts: contracts, chain: chain)
            }
        }
        
        // Step 2: For any THORChain asset without a price, try the THORChain pools
        let thorchainCoinsWithoutPrices = coins.filter { coin in
            // Check if this coin is on THORChain
            guard coin.chain == .thorChain else { return false }
            
            // Check if it already has a price from normal sources
            let hasPrice = RateProvider.shared.rate(for: coin) != nil
            return !hasPrice
        }
        
        if !thorchainCoinsWithoutPrices.isEmpty {
            try await fetchThorchainAssetPrice(coins: thorchainCoinsWithoutPrices)
        }
        
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
    
    func fetchPrices(ids: [String]) async throws {
        let idsQuery = ids
            .filter { !$0.isEmpty }
            .joined(separator: ",")
        
        let currencies = SettingsCurrency.allCases
            .map { $0.rawValue }
            .joined(separator: ",")
        
        let url = Endpoint.fetchCryptoPrices(
            ids: idsQuery,
            currencies: currencies
        )
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode([String: [String: Double]].self, from: data)
            
            try await RateProvider.shared.save(rates: mapRates(response: response))
        } catch {
            if let error = error as? URLError, error.code == .cancelled {
                print("request cancelled")
            } else {
                throw error
            }
        }
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
