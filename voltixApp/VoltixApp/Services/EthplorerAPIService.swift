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
        
        let urlString = "https://api.ethplorer.io/getAddressInfo/\(address)?apiKey=freekey"
        
        print(urlString)
        
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.errorMessage = "Invalid URL"
                print(String(describing: self.errorMessage))
            }
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            // Print raw JSON string for debugging
            if let jsonStr = String(data: data, encoding: .utf8) {
                // print("Raw JSON string: \(jsonStr)")
            }
            
            let decodedData = try JSONDecoder().decode(EthAddressInfo.self, from: data)
            
            DispatchQueue.main.async {
                self.addressInfo = decodedData
                // print(self.addressInfo?.toString() ?? "ERROR")
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
