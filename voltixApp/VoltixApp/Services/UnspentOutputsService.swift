import Foundation
import SwiftUI

@MainActor
public class UnspentOutputsService: ObservableObject {
    @Published var walletData: BitcoinTransaction?
    @Published var errorMessage: String?
    
    // Dictionary to store cache entries with address as the key
    private var cache: [String: CacheEntry] = [:]
    
    // Function to check if cache for a given address is valid (not older than 1 minutes)
    private func isCacheValid(for address: String) -> Bool {
        if let entry = cache[address], -entry.timestamp.timeIntervalSinceNow < 60 {
            return true // Cache is valid if less than 5 minutes old
        }
        return false
    }
    
    // Replace with your actual function to fetch unspent outputs
    func fetchUnspentOutputs(for address: String) async {
        // Use cache if it's valid for the requested address
        if isCacheValid(for: address), let cachedData = cache[address]?.data {
            self.walletData = cachedData
            return
        }
        
        // Construct the URL
        guard let url = URL(string: "https://api.blockcypher.com/v1/btc/main/addrs/\(address)?unspentOnly=true") else {
            print("Invalid URL")
            return
        }
        
        do {
            // Fetch data from the URL
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            let decodedData = try decoder.decode(BitcoinTransaction.self, from: data)
            
            // Update the cache with new data and current timestamp for the address
            cache[address] = CacheEntry(data: decodedData, timestamp: Date())
            
            // Update your published property with the decoded data
            self.walletData = decodedData
        } catch {
            print("Fetch failed: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
        }
    }
}

// Cache structure to hold data and timestamp
fileprivate struct CacheEntry {
    let data: BitcoinTransaction
    let timestamp: Date
}
