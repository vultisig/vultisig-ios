import Foundation
import SwiftUI

@MainActor
public class CryptoPriceService: ObservableObject {
    
    public static let shared = CryptoPriceService()
    
    private var cache: ThreadSafeDictionary<String, (data: CryptoPrice, timestamp: Date)> = ThreadSafeDictionary()
    
    private var cacheTokens: ThreadSafeDictionary<String, (data: CryptoPrice, timestamp: Date)> = ThreadSafeDictionary()
    
    private let CACHE_TIMEOUT_IN_SECONDS: Double = 60 * 60
    
    private func getCacheTokenKey(contractAddresses: [String], chain: Chain) -> String {
        let fiat = SettingsCurrency.current.rawValue.lowercased()
        let sortedAddresses = contractAddresses.sorted().joined(separator: "_")
        return "\(sortedAddresses)_\(chain.name.lowercased())_\(fiat)"
    }
    
    private func getCachedTokenPrices(contractAddresses: [String], chain: Chain) async -> CryptoPrice? {
        let cacheKey = getCacheTokenKey(contractAddresses: contractAddresses, chain: chain)
        return await Utils.getCachedData(cacheKey: cacheKey, cache: cacheTokens, timeInSeconds: CACHE_TIMEOUT_IN_SECONDS)
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
    private func getAllTokenPricesCoinGecko() async -> CryptoPrice? {
        let tokens = getCoins().filter { !$0.isNativeToken }
        let tokenGroups = Dictionary(grouping: tokens, by: { $0.chain })
        let allTokenPrices = CryptoPrice(prices: [:])
        
        for (chain, tokensInChain) in tokenGroups {
            let contractAddresses = tokensInChain.map { $0.contractAddress }.filter{!$0.isEmpty}
            if contractAddresses.count == 0 {
                continue
            }
            if let prices = await fetchCoingeckoTokenPrices(contractAddresses: contractAddresses, chain: chain) {
                allTokenPrices.prices.merge(prices.prices) { (current, _) in current }
            }
        }
        
        return allTokenPrices
    }
    
    func fetchCoingeckoPoolPrice(chain: Chain, contractAddress: String) async throws -> (image_url: String?, coingecko_coin_id: String?, price_usd: Double?) {
        
        // Fetch the price from the network if not in cache
        do {
            struct Response: Codable {
                struct Data: Codable {
                    struct Attributes: Codable {
                        let image_url: String?
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
                if let priceRate = response.attributes.price_usd {
                    return (image_url: response.attributes.image_url, coingecko_coin_id: nil, price_usd: Double(priceRate))
                }
            }
        } catch {
            print(error.localizedDescription)
            return (image_url: nil, coingecko_coin_id: nil, price_usd: nil)
        }
        
        return (image_url: nil, coingecko_coin_id: nil, price_usd: nil)
    }
    
    func getTokenPrice(coin: Coin) async -> Double {
        
        // Those tokens are the ones in the vault, so we should cache them if not cached
        let vaultTokens = await getAllTokenPricesCoinGecko()
        let vaultPrice = vaultTokens?.prices[coin.contractAddress]?[SettingsCurrency.current.rawValue.lowercased()]
        
        guard let price = vaultPrice else {
            let prices = await fetchCoingeckoTokenPrices(contractAddresses: [coin.contractAddress], chain: coin.chain)
            return prices?.prices[coin.contractAddress]?[SettingsCurrency.current.rawValue.lowercased()] ?? .zero
        }
        
        return price
    }
    private func getCoinGeckoPlatform(chain:Chain) -> String{
        switch chain{
        case .thorChain,.solana,.bitcoin,.bitcoinCash,.litecoin,.dogecoin,.dash,.gaiaChain,.kujira,.mayaChain,.cronosChain,.polkadot,.dydx,.sui:
            return ""
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
        case .polygon:
            return "polygon-pos"
        case .optimism:
            return "optimistic-ethereum"
        case .bscChain:
            return "binance-smart-chain"
        case .zksync:
            return "zksync"
        }
    }
    private func fetchCoingeckoTokenPrices(contractAddresses: [String], chain: Chain) async -> CryptoPrice? {
        let tokenPrices = CryptoPrice(prices: [:])
        let fiat = SettingsCurrency.current.rawValue.lowercased()
        do {
            // Create a cache key for all contract addresses combined
            if let cacheEntry = await getCachedTokenPrices(contractAddresses: contractAddresses, chain: chain) {
                return cacheEntry
            }
            
            // If no cache entry is found, fetch the prices for all contract addresses
            let urlString = Endpoint.fetchTokenPrice(network: getCoinGeckoPlatform(chain: chain), addresses: contractAddresses, fiat: fiat)
            let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
            
            for address in contractAddresses {
                if let result = Utils.extractResultFromJson(fromData: data, path: "\(address.lowercased()).\(fiat)"),
                   let resultNumber = result as? NSNumber {
                    let fiatPrice = Double(resultNumber.doubleValue)
                    tokenPrices.prices[address] = [fiat: fiatPrice]
                } else {
                    print("JSON decoding error for \(address)")
                }
            }
            
            // Cache the combined result
            let cacheKey = getCacheTokenKey(contractAddresses: contractAddresses, chain: chain)
            cacheTokens.set(cacheKey, (data: tokenPrices, timestamp: Date()))
            
            return tokenPrices
            
        } catch {
            print("Fail to fetch coin gecko prices: \(error.localizedDescription)")
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
            print("fail to get crypto price: \(error)")
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
