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
                print(self.errorMessage)
            }
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
                // Print raw JSON string for debugging
            if let jsonStr = String(data: data, encoding: .utf8) {
                print("Raw JSON string: \(jsonStr)")
            }
            
            let decodedData = try JSONDecoder().decode(EthAddressInfo.self, from: data)
            DispatchQueue.main.async {
                self.addressInfo = decodedData
                print(self.addressInfo?.toString() ?? "ERROR")
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
                print(self.errorMessage ?? "Unknown error")
            }
        }
        
        
    }
}
struct EthAddressInfo: Codable {
    let address: String
    let ETH: ETHInfo
    let tokens: [Token]
    
    struct ETHInfo: Codable {
        let price: Price
        let balance: Double
        let rawBalance: String
        
        var balanceString: String {
            return "\(String(format: "%.8f", balance))" // Wei is too long
        }
        
        var balanceInUsd: String {
            let ethBalanceInUsd = balance * price.rate
            return "US$ \(String(format: "%.2f", ethBalanceInUsd))"
        }
        
        func getAmountInUsd(_ amount: Double) -> String {
            let ethAmountInUsd = amount * price.rate
            return "\(String(format: "%.2f", ethAmountInUsd))"
        }
        
        func getAmountInEth(_ usdAmount: Double) -> String {
            let ethRate = price.rate
            let amountInEth = usdAmount / ethRate
            return "\(String(format: "%.4f", amountInEth))"
        }

    }
    
    struct Token: Codable {
        let tokenInfo: TokenInfo
        let balance: Int // If always integer in JSON
        let rawBalance: String
        
        var balanceDecimal: Double {
            let tokenBalance = Double(rawBalance) ?? 0.0
            let tokenDecimals = Double(tokenInfo.decimals) ?? 0.0
            let balanceInDecimal = (tokenBalance / pow(10, tokenDecimals))
            return balanceInDecimal
        }
        
        var balanceString: String {
            let tokenBalance = Double(rawBalance) ?? 0.0
            let tokenDecimals = Double(tokenInfo.decimals) ?? 0.0
            let balanceInDecimal = (tokenBalance / pow(10, tokenDecimals))
            return String(format: "%.\(tokenInfo.decimals)f", balanceInDecimal)
        }
        
        func getAmountInUsd(_ amount: Double) -> String {
            let tokenRate = tokenInfo.price.rate
            // let tokenDecimals = Double(tokenInfo.decimals) ?? 0.0
            // let balanceInUsd = (amount / pow(10, tokenDecimals)) * tokenRate
            let balanceInUsd = amount * tokenRate
            return "\(String(format: "%.2f", balanceInUsd))"
        }
        
        func getAmountInTokens(_ usdAmount: Double) -> String {
            let tokenRate = tokenInfo.price.rate
            // let tokenDecimals = Double(tokenInfo.decimals) ?? 0.0
            let tokenAmount = (usdAmount / tokenRate) // * pow(10, tokenDecimals)
            return "\(String(format: "%.\(tokenInfo.decimals)f", tokenAmount))"
        }

        var balanceInUsd: String {
            let tokenBalance = Double(rawBalance) ?? 0.0
            let tokenRate = tokenInfo.price.rate
            let tokenDecimals = Double(tokenInfo.decimals) ?? 0.0
            let balanceInUsd = (tokenBalance / pow(10, tokenDecimals)) * tokenRate
            
            return "US$ \(String(format: "%.2f", balanceInUsd))"
        }
    }
    
    struct TokenInfo: Codable {
        let address: String
        let name: String
        let decimals: String
        let symbol: String
        let totalSupply: String
        let owner: String
        let lastUpdated: Int
        let price: Price
    }
    
    struct Price: Codable {
        let rate: Double
        let diff: Double
        let diff7d: Double
        let ts: Int
        let marketCapUsd: Double
        let availableSupply: Double
        let volume24h: Double
    }
    
    func toString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        do {
            let jsonData = try encoder.encode(self)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        } catch {
            print("Error encoding JSON: \(error)")
            return "Error encoding JSON: \(error)"
        }
        return ""
    }
}
