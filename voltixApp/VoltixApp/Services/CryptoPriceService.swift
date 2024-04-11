import Foundation
import SwiftUI

@MainActor
public class CryptoPriceService: ObservableObject {

	public static let shared = CryptoPriceService()
    
	// Dictionary to hold cached data and their timestamps
	private var cache: [String: (data: CryptoPrice, timestamp: Date)] = [:]
	
	private init() {}
	
	private func isCacheValid(for key: String) -> Bool {
		guard let cacheEntry = cache[key] else { return false }
		let elapsedTime = Date().timeIntervalSince(cacheEntry.timestamp)
		return elapsedTime <= 3600 // 1 hour in seconds
	}
    
    var defaultCurrency: String {
        return UserDefaults.standard.string(forKey: "currency") ?? SettingsCurrency.USD.description()
    }
    
    
    func getPrice(priceProviderId: String) async -> Double {
        print("Current currency: \(defaultCurrency)")
        
        let cryptoPrices = await fetchAllCryptoPrices()
        return cryptoPrices?.prices[priceProviderId]?[defaultCurrency] ?? Double.zero
    }
	
	func fetchAllCryptoPrices() async -> CryptoPrice? {
		guard let vault = ApplicationState.shared.currentVault else {
			print("current vault is nil")
			return nil
		}
		
		let coins = vault.coins.map { $0.priceProviderId }.joined(separator: ",")
		
        return await fetchCryptoPrices(for: coins, for: defaultCurrency)
	}
	
	func fetchCryptoPrices(for coin: String = "bitcoin", for fiat: String = "usd") async -> CryptoPrice? {
		let cacheKey = "\(coin)-\(fiat)"
		
		if let cacheEntry = cache[cacheKey], isCacheValid(for: cacheKey) {
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
            print(error.localizedDescription)
            return nil
		}
	}
}
