import Foundation
import SwiftUI

@MainActor
public class CryptoPriceService: ObservableObject {
    
    public static let shared = CryptoPriceService()
    
    private var cache: [String: (data: CryptoPrice, timestamp: Date)] = [:]
    
    private var cacheTokens: [String: (data: [String: Double], timestamp: Date)] = [:]
    
    private init() {}
    
    func getPrice(priceProviderId: String) async -> Double {
        
        if priceProviderId.isEmpty {
            return Double.zero
        }
        
        var price = Double.zero
        
        if let priceCoinGecko = await getAllCryptoPricesCoinGecko() {
            price = priceCoinGecko.prices[priceProviderId]?[SettingsCurrency.current.rawValue.lowercased()] ?? Double.zero
        } else if let priceCoinPaprika = await getAllCryptoPricesCoinPaprika() {
            price = priceCoinPaprika.prices[priceProviderId]?[SettingsCurrency.current.rawValue.lowercased()] ?? Double.zero
        }
        
        return price
    }
    
    func fetchCoingeckoPoolPrice(chain: Chain, contractAddress: String) async throws -> (image_url: String?, coingecko_coin_id: String?, price_usd: Double?) {
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
                return (response.attributes.image_url, response.attributes.coingecko_coin_id, priceRate)
            }

        } catch {
            print(error.localizedDescription)
            return (image_url: nil, coingecko_coin_id: nil, price_usd: nil)
        }
        return (image_url: nil, coingecko_coin_id: nil, price_usd: nil)
    }
    
    func fetchCoingeckoId(chain: Chain, addresses: [String]) async throws -> [String?] {
        struct Response: Codable {
            struct Data: Codable {
                struct Attributes: Codable {
                    let coingecko_coin_id: String?
                }
                let attributes: Attributes
            }
            let data: [Data]
        }
        let response: Response = try await Utils.fetchObject(from: Endpoint.fetchTokensInfo(
            network: chain.coingeckoId,
            addresses: addresses)
        )
        return response.data.map { $0.attributes.coingecko_coin_id }
    }
    
    func getTokenPrice(coin: Coin) async -> Double {
        let fiat = SettingsCurrency.current.rawValue.lowercased()
        let key = "\(coin.contractAddress)_\(coin.chain.name)_\(fiat)"
        let pricesCoinGecko = await getAllTokenPricesCoinGecko()
        
        if pricesCoinGecko.isEmpty {
            let prices = await fetchCoingeckoTokenPrice(contractAddresses: [coin.contractAddress], chain: coin.chain)
            return prices[key] ?? .zero
        }
        
        let price = pricesCoinGecko[key]
        return price ?? .zero
    }
    
    private func getAllTokenPricesCoinGecko() async -> [String: Double] {
        
        let fiat = SettingsCurrency.current.rawValue.lowercased()
        let tokens = getCoins().filter {!$0.isNativeToken }
        let tokenGroups = Dictionary(grouping: tokens, by: { $0.chain })
        
        var allTokenPrices: [String: Double] = [:]
        
        for (chain, tokensInChain) in tokenGroups {
            let contractAddresses = tokensInChain.map { $0.contractAddress }
            let prices = await fetchCoingeckoTokenPrice(contractAddresses: contractAddresses, chain: chain)
            for (address, price) in prices {
                let key = "\(address)_\(chain.name)_\(fiat)"
                allTokenPrices[key] = price
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000_000) // 1 second delay, should not throw
        }
        
        return allTokenPrices
    }
    
    private func fetchCoingeckoTokenPrice(contractAddresses: [String], chain: Chain) async -> [String: Double] {
        var tokenPrices: [String: Double] = [:]
        
        do {
            let fiat = SettingsCurrency.current.rawValue.lowercased()
            
            // Create a cache key for each contract address individually
            for address in contractAddresses {
                let cacheKey = "\(address)_\(chain.name)_\(fiat)"
                
                if let cacheEntry = cacheTokens[cacheKey], isCacheValid(for: cacheKey) {
                    print("Price from cache tokens")
                    tokenPrices[address] = cacheEntry.data[address]
                    continue
                }
            }
            
            // If no cache entry is found, fetch the prices for all contract addresses
            let urlString = Endpoint.fetchTokenPrice(network: chain.name, addresses: contractAddresses, fiat: fiat)
            let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
            
            for address in contractAddresses {
                if let result = Utils.extractResultFromJson(fromData: data, path: "\(address).\(SettingsCurrency.current.rawValue.lowercased())"),
                   let resultNumber = result as? NSNumber {
                    let fiatPrice = Double(resultNumber.doubleValue)
                    tokenPrices[address] = fiatPrice
                    
                    // Cache the price for each contract address individually
                    let cacheKey = "\(address)_\(chain.name)_\(fiat)"
                    self.cacheTokens[cacheKey] = (data: [address: fiatPrice], timestamp: Date())
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
    
    private func getAllCryptoPricesCoinPaprika() async -> CryptoPrice? {
        do {
            let coins = getCoins()
            
            let key = coins.map { $0.priceProviderId }.joined(separator: ",")
            
            let fiat = SettingsCurrency.current.rawValue.lowercased()
            
            let cacheKey = "\(key)-\(fiat)"
            
            if let cacheEntry = cache[cacheKey], isCacheValid(for: cacheKey) {
                print("Price from cache coin PAPRIKA")
                return cacheEntry.data
            }
            
            let coinPaprikaCoins = getCoinPaprikaCoins(coins: coins)
            let coinPaprikaQuotes = try await fetchAllCryptoPricesCoinPaprika(coins: coinPaprikaCoins)
            if let pricesCoinPaprika = coinPaprikaQuotes {
                self.cache[cacheKey] = (data: pricesCoinPaprika, timestamp: Date())
                return pricesCoinPaprika
            }
            return nil
        } catch {
            print(error.localizedDescription)
        }
        return nil
        
    }
    
    private func fetchAllCryptoPricesCoinGecko(for coin: String = "bitcoin", for fiat: String = "usd") async -> CryptoPrice? {
        
        let cacheKey = "\(coin)-\(fiat)"
        
        if let cacheEntry = cache[cacheKey], isCacheValid(for: cacheKey) {
            print("Price from cache coin Gecko")
            return cacheEntry.data
        }
        
        let urlString = Endpoint.fetchCryptoPrices(coin: coin, fiat: fiat)
        
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decodedData = try JSONDecoder().decode(CryptoPrice.self, from: data)
            self.cache[cacheKey] = (data: decodedData, timestamp: Date())
            return decodedData
        } catch {
            return nil
        }
    }
    
    private func fetchAllCryptoPricesCoinPaprika(coins: [CoinPaprikaCoin]) async throws -> CryptoPrice? {
        
        let coinPaprikaQuotes: [CoinPaprikaQuote] = try await Utils.fetchArray(from: Endpoint.fetchCoinPaprikaQuotes(SettingsCurrency.current.rawValue.lowercased()))
        
        var prices : [String: [String: Double]] = [:]
        
        let coinIds = coins.map { $0.id }
        
        _ = coinPaprikaQuotes.filter { quote in
            coinIds.contains(quote.id)
        }.map { coin in
            coin.priceProviderId = coins.first{ $0.id == coin.id }?.priceProviderId
            
            if let priceProviderId = coin.priceProviderId{
                let currency = SettingsCurrency.current.rawValue
                if let price = coin.quotes[currency]?.price {
                    prices[priceProviderId] = [currency.lowercased(): price]
                }
            }
            
        }
        
        return CryptoPrice(prices: prices)
    }
    
    private func getCoinPaprikaCoins(coins: [Coin]) -> [CoinPaprikaCoin] {
        guard let url = Bundle.main.url(forResource: "coinpaprika", withExtension: "json") else {
            print("Failed to locate coinpaprika.json in bundle.")
            return []
        }
        
        let tickers = coins.map{$0.ticker}
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601 // For decoding ISO 8601 date strings
            let cryptoData = try decoder.decode([CoinPaprikaCoin].self, from: data)
            
            let paprikaCoins = cryptoData.filter { crypto in
                tickers.map({ $0.uppercased()}).contains(crypto.symbol.uppercased())
            }.map{ paprikaCoin in
                let systemCoin = coins.first{$0.ticker == paprikaCoin.symbol}
                paprikaCoin.priceProviderId = systemCoin?.priceProviderId ?? .empty
                return paprikaCoin
            }
            
            return paprikaCoins
        } catch {
            print("Failed to load or decode the JSON:", error)
        }
        return []
    }
    
    private func getCoins() -> [Coin]{
        guard let vault = ApplicationState.shared.currentVault else {
            print("current vault is nil")
            return []
        }
        
        return vault.coins
    }
    
    private func isCacheValid(for key: String) -> Bool {
        guard let cacheEntry = cache[key] else { return false }
        let elapsedTime = Date().timeIntervalSince(cacheEntry.timestamp)
        return elapsedTime <= 120 // 1 hour in seconds
    }
}
