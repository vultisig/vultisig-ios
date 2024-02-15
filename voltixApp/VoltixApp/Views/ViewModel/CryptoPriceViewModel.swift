//
//  CoinGeckoApiViewModel.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 14/02/2024.
//

import Foundation
import SwiftUI

@MainActor
public class CryptoPriceViewModel: ObservableObject {
    @Published var cryptoPrices: CryptoPriceData?
    @Published var errorMessage: String?

    // Dictionary to hold cached data and their timestamps
    private var cache: [String: (data: CryptoPriceData, timestamp: Date)] = [:]

    private func isCacheValid(for key: String) -> Bool {
        guard let cacheEntry = cache[key] else { return false }
        let elapsedTime = Date().timeIntervalSince(cacheEntry.timestamp)
        return elapsedTime <= 3600 // 1 hour in seconds
    }

    func fetchCryptoPrices(for coin: String = "bitcoin", for fiat: String = "usd") async {
        let cacheKey = "\(coin)-\(fiat)"
        
        // Check cache validity
        if let cacheEntry = cache[cacheKey], isCacheValid(for: cacheKey) {
            self.cryptoPrices = cacheEntry.data
            return
        }
        
        let urlString = "https://api.coingecko.com/api/v3/simple/price?ids=\(coin)&vs_currencies=\(fiat)"
        
        guard let url = URL(string: urlString) else {
            self.errorMessage = "Invalid URL"
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decodedData = try JSONDecoder().decode(CryptoPriceData.self, from: data)
            DispatchQueue.main.async {
                self.cryptoPrices = decodedData
                // Update cache with new data and current timestamp
                self.cache[cacheKey] = (data: decodedData, timestamp: Date())
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
