import Foundation
import SwiftUI

@MainActor
public class EthplorerAPIService: ObservableObject {
    @Published var addressInfo: EthAddressInfo?
    @Published var errorMessage: String?
    
    private var cache: [String: (data: EthAddressInfo, timestamp: Date)] = [:]
    
    private func isCacheValid(for key: String) -> Bool {
        guard let cacheEntry = cache[key] else { return false }
        let elapsedTime = Date().timeIntervalSince(cacheEntry.timestamp)
        return elapsedTime <= 60 // 1 hour in seconds
    }
    
    func getEthInfo(for address: String) async {
        let cacheKey = "\(address)"
        
        if let cacheEntry = cache[cacheKey], isCacheValid(for: cacheKey) {
            self.addressInfo = cacheEntry.data
            return
        }
        
        let urlString = Endpoint.getEthInfo(address)
        
        // print(urlString)
        
        guard let url = URL(string: urlString) else {
            self.errorMessage = "Invalid URL"
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decodedData = try JSONDecoder().decode(EthAddressInfo.self, from: data)
            self.addressInfo = decodedData
            self.cache[cacheKey] = (data: decodedData, timestamp: Date())
            
        } catch {
            self.errorMessage = Utils.handleJsonDecodingError(error)
        }
    }
}
