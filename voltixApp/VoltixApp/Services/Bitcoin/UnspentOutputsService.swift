import Foundation
import SwiftUI

@MainActor
public class UnspentOutputsService: ObservableObject {
    @Published var walletData: BitcoinTransaction?
    @Published var errorMessage: String?
    
    // Dictionary to store cache entries with address as the key
    private var cache: [String: UTXOCacheEntry] = [:]
    
    // Function to check if cache for a given address is valid (not older than 1 minutes)
    private func isCacheValid(for address: String) -> Bool {
        
        if let entry = cache[address], -entry.timestamp.timeIntervalSinceNow < 60 {
            return true // Cache is valid if less than 5 minutes old
        }
        
        return false
    }
    
    func fetchUnspentOutputs(for address: String) async {
        if isCacheValid(for: address), let cachedData = cache[address]?.data {
            self.walletData = cachedData
            return
        }
        
        guard let url = URL(string: Endpoint.fetchUnspentOutputs(address)) else {
            print("Invalid URL")
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
			print(String(data: data, encoding: String.Encoding.utf8))
			let decoder = JSONDecoder()
            let decodedData = try decoder.decode(BitcoinTransaction.self, from: data)
            cache[address] = UTXOCacheEntry(data: decodedData, timestamp: Date())
            self.walletData = decodedData
        } catch {
            print("Fetch failed: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
        }
    }
}

fileprivate struct UTXOCacheEntry {
    let data: BitcoinTransaction
    let timestamp: Date
}
