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
    
    func fetchCryptoPrices(for coin: String = "bitcoin", for fiat: String = "usd") async {
        let cacheKey = "\(coin)-\(fiat)"
        
        // Check cache validity
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
            //print(data)
            
            let decodedData = try JSONDecoder().decode(CryptoPrice.self, from: data)
            
            DispatchQueue.main.async {
                self.cryptoPrices = decodedData
                // Update cache with new data and current timestamp
                self.cache[cacheKey] = (data: decodedData, timestamp: Date())
            }
        } catch {
            DispatchQueue.main.async {
                let errorDescription: String
                
                switch error {
                case let DecodingError.dataCorrupted(context):
                    errorDescription = "Data corrupted: \(context)"
                case let DecodingError.keyNotFound(key, context):
                    errorDescription = "Key '\(key)' not found: \(context.debugDescription), path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
                case let DecodingError.valueNotFound(value, context):
                    errorDescription = "Value '\(value)' not found: \(context.debugDescription), path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
                case let DecodingError.typeMismatch(type, context):
                    let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                    errorDescription = "Type '\(type)' mismatch: \(context.debugDescription), path: \(path)"
                default:
                    errorDescription = "Error: \(error.localizedDescription)"
                }
                
                self.errorMessage = errorDescription
                // print(self.errorMessage ?? "Unknown error")
            }
        }
    }
}
