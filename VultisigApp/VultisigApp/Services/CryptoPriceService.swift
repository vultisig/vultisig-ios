import Foundation
import SwiftUI

@MainActor
public class CryptoPriceService: ObservableObject {
    
    public static let shared = CryptoPriceService()
    
    private var cache: ThreadSafeDictionary<String, (data: CryptoPrice, timestamp: Date)> = ThreadSafeDictionary()
    
    private var cacheTokens: ThreadSafeDictionary<String, (data: [String: Double], timestamp: Date)> = ThreadSafeDictionary()
    
    private let CACHE_TIMEOUT_IN_SECONDS: Double = 60 * 60
    
    private func getCacheTokenKey(contractAddress: String, chain: Chain) -> String {
        let fiat = SettingsCurrency.current.rawValue.lowercased()
        return "\(contractAddress)_\(chain.name.lowercased())_\(fiat)"
    }
    
    private func getCachedTokenPrice(contractAddress: String, chain: Chain) async -> Double? {
        let cacheKey = getCacheTokenKey(contractAddress: contractAddress, chain: chain)
        if let cacheEntry = await Utils.getCachedData(cacheKey: cacheKey, cache: cacheTokens, timeInSeconds: CACHE_TIMEOUT_IN_SECONDS) {
            return cacheEntry[contractAddress]
        }
        return nil
    }
    
    private init() {}
    
    func getPrice(priceProviderId: String) async -> Double {
        
        if priceProviderId.isEmpty {
            return Double.zero
        }
        
        var price = Double.zero
        
        if let priceCoinGecko = await getAllCryptoPricesCoinGecko() {
            price = priceCoinGecko.prices[priceProviderId]?[SettingsCurrency.current.rawValue.lowercased()] ?? Double.zero
        }
        
        return price
    }
    
    // This function should prevent any rate limit on the CoinGecko API
    // It fetches the prices of all tokens in the vault in bulk per chain
    private func getAllTokenPricesCoinGecko() async -> [String: Double] {
        let tokens = getCoins().filter { !$0.isNativeToken }
        let tokenGroups = Dictionary(grouping: tokens, by: { $0.chain })
        
        var allTokenPrices: [String: Double] = [:]
        
        for (chain, tokensInChain) in tokenGroups {
            let contractAddresses = tokensInChain.map { $0.contractAddress }
            let prices = await fetchCoingeckoTokenPrice(contractAddresses: contractAddresses, chain: chain)
            for (address, price) in prices {
                let cacheKey = getCacheTokenKey(contractAddress: address, chain: chain)
                allTokenPrices[cacheKey] = price
            }
        }
        
        return allTokenPrices
    }
    
    func fetchCoingeckoPoolPrice(chain: Chain, contractAddress: String) async throws -> (image_url: String?, coingecko_coin_id: String?, price_usd: Double?) {
        
        let cacheKey = getCacheTokenKey(contractAddress: contractAddress, chain: chain)
        
        // Check if the price is cached and valid
        if let cacheEntry = await getCachedTokenPrice(contractAddress: contractAddress, chain: chain) {
            return (image_url: nil, coingecko_coin_id: nil, price_usd: cacheEntry)
        }
        
        // Fetch the price from the network if not in cache
        do {
            struct Response: Codable {
                struct Data: Codable {
                    struct Attributes: Codable {
                        let image_url: String?
                        let coingecko_coin_id: String?
                        let price_usd: String?
                    }
                    let attributes: Attributes
                }
                let data: [Data]
            }
            
            let response: Response = try await Utils.fetchObject(from: Endpoint.fetchTokensInfo(
                network: chain.coingeckoId,
                addresses: [contractAddress])
            )
            
            if let response = response.data.first {
                let priceRate = response.attributes.price_usd.flatMap { Double($0) }
                
                // Cache the fetched price
                if let priceRate = priceRate {
                    cacheTokens.set(cacheKey, (data: [contractAddress: priceRate], timestamp: Date()))
                }
                
                return (response.attributes.image_url, response.attributes.coingecko_coin_id, priceRate)
            }
        } catch {
            print(error.localizedDescription)
            return (image_url: nil, coingecko_coin_id: nil, price_usd: nil)
        }
        
        return (image_url: nil, coingecko_coin_id: nil, price_usd: nil)
    }
    
    func getTokenPrice(coin: Coin) async -> Double {
        let cacheKey = getCacheTokenKey(contractAddress: coin.contractAddress, chain: coin.chain)
        
        // Those tokens are the ones in the vault, so we should cache them if not cached
        let vaultTokens = await getAllTokenPricesCoinGecko()
        let vaultPrice = vaultTokens[coin.contractAddress]
        
        guard let price = vaultPrice else {
            let prices = await fetchCoingeckoTokenPrice(contractAddresses: [coin.contractAddress], chain: coin.chain)
            return prices[cacheKey] ?? .zero
        }
        
        return price
    }
    
    private func fetchCoingeckoTokenPrice(contractAddresses: [String], chain: Chain) async -> [String: Double] {
        var tokenPrices: [String: Double] = [:]
        let fiat = SettingsCurrency.current.rawValue.lowercased()
        do {
            // Create a cache key for each contract address individually
            for address in contractAddresses {
                if let cacheEntry = await getCachedTokenPrice(contractAddress: address, chain: chain) {
                    tokenPrices[address] = cacheEntry
                }
            }
            
            // If all cached, then return
            if contractAddresses.count == tokenPrices.count {
                return tokenPrices
            }
            
            // If no cache entry is found, fetch the prices for all contract addresses
            let urlString = Endpoint.fetchTokenPrice(network: chain.name, addresses: contractAddresses, fiat: fiat)
            let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
            
            // Should not get the price to the coins already in the cache
            for address in contractAddresses.filter({ !tokenPrices.keys.contains($0) }) {
                if let result = Utils.extractResultFromJson(fromData: data, path: "\(address).\(fiat)"),
                   let resultNumber = result as? NSNumber {
                    let fiatPrice = Double(resultNumber.doubleValue)
                    tokenPrices[address] = fiatPrice
                    
                    // Cache the price for each contract address individually
                    let cacheKey = getCacheTokenKey(contractAddress: address, chain: chain)
                    print("fetchCoingeckoTokenPrice > FROM WEB: \(cacheKey)")
                    
                    cacheTokens.set(cacheKey, (data: [address: fiatPrice], timestamp: Date()))
                } else {
                    print("JSON decoding error for \(address)")
                }
            }
            
            return tokenPrices
            
        } catch {
            print(error.localizedDescription)
        }
        
        return tokenPrices
    }
    
    private func getAllCryptoPricesCoinGecko() async -> CryptoPrice? {
        let coins = getCoins().map { $0.priceProviderId }.joined(separator: ",")
        return await fetchAllCryptoPricesCoinGecko(for: coins, for: SettingsCurrency.current.rawValue.lowercased())
    }
    
    private func fetchAllCryptoPricesCoinGecko(for coin: String = "bitcoin", for fiat: String = "usd") async -> CryptoPrice? {
        
        let cacheKey = "\(coin)-\(fiat)"
        if let cacheEntry = await Utils.getCachedData(cacheKey: cacheKey, cache: cache, timeInSeconds: CACHE_TIMEOUT_IN_SECONDS) {
            print("Price from cache coin Gecko native token \(cacheKey)")
            return cacheEntry
        }
        
        let urlString = Endpoint.fetchCryptoPrices(coin: coin, fiat: fiat)
        
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decodedData = try JSONDecoder().decode(CryptoPrice.self, from: data)
            cache.set(cacheKey, (data: decodedData, timestamp: Date()))
            return decodedData
        } catch {
            return nil
        }
    }
    
    private func getCoins() -> [Coin] {
        guard let vault = ApplicationState.shared.currentVault else {
            print("current vault is nil")
            return []
        }
        
        return vault.coins
    }
}
