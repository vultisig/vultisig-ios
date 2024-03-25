import Foundation
import SwiftUI

@MainActor
public class CryptoPriceService: ObservableObject {
	
	@Published var cryptoPrices: CryptoPrice?
	@Published var errorMessage: String?
	
	public static let shared = CryptoPriceService()
	
	// Dictionary to hold cached data and their timestamps
	private var cache: [String: (data: CryptoPrice, timestamp: Date)] = [:]
	
	private init() {}
	
	private func isCacheValid(for key: String) -> Bool {
		guard let cacheEntry = cache[key] else { return false }
		let elapsedTime = Date().timeIntervalSince(cacheEntry.timestamp)
		return elapsedTime <= 3600 // 1 hour in seconds
	}
	
	func fetchCryptoPrices() async {
		guard let vault = ApplicationState.shared.currentVault else {
			print("current vault is nil")
			return
		}
		
		let coins = vault.coins.map { $0.priceProviderId }.joined(separator: ",")
		
		await fetchCryptoPrices(for: coins, for: "usd")
	}
	
	func fetchCryptoPrices(for coin: String = "bitcoin", for fiat: String = "usd") async {
		let cacheKey = "\(coin)-\(fiat)"
		
		if let cacheEntry = cache[cacheKey], isCacheValid(for: cacheKey) {
			print("Crypto Price Service > The data came from the cache !!")
			self.cryptoPrices = cacheEntry.data
			return
		}
		
		let urlString = Endpoint.fetchCryptoPrices(coin: coin, fiat: fiat)
		
		guard let url = URL(string: urlString) else {
			self.errorMessage = "Invalid URL"
			return
		}
		
		do {
			let (data, _) = try await URLSession.shared.data(from: url)
			
			if let jsonStr = String(data: data, encoding: .utf8) {
				print("Crypto Price Service > Raw JSON string: \(jsonStr)")
			}
			
			let decodedData = try JSONDecoder().decode(CryptoPrice.self, from: data)
			
			DispatchQueue.main.async {
				self.cryptoPrices = decodedData
				self.cache[cacheKey] = (data: decodedData, timestamp: Date())
			}
		} catch {
			self.errorMessage = Utils.handleJsonDecodingError(error)
		}
	}
}
