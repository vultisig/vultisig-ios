import Foundation
import SwiftUI

// MARK: - SolanaService

@MainActor
class SolanaService: ObservableObject {
    static let shared = SolanaService()
    private init() {}
	
    @Published var transactionResult: String?
    @Published var balance: Int?
    @Published var recentBlockHash: String?
    @Published var feeInLamports: String?
    
    var rawBalance: String {
        if let balance = balance {
            return "\(balance)"
        } else {
            return "0"
        }
    }
	
    func solBalanceInUSD(usdPrice: Double?, includeCurrencySymbol: Bool = true) -> String? {
        guard let usdPrice = usdPrice,
              let solBalance = balance else { return nil }
		
        let balanceSOL = Double(solBalance) / 1_000_000_000.0
        let balanceUSD = balanceSOL * usdPrice
		
        let formatter = NumberFormatter()
		
        if includeCurrencySymbol {
            formatter.numberStyle = .currency
            formatter.currencyCode = "USD"
        } else {
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
            formatter.decimalSeparator = "."
            formatter.groupingSeparator = ""
        }
		
        return formatter.string(from: NSNumber(value: balanceUSD))
    }
	
    var formattedSolBalance: String? {
        guard let solAmountInt = balance else {
            return "Balance not available"
        }
		
        let solAmount = Double(solAmountInt)
        let balanceSOL = solAmount / 1_000_000_000.0 // Adjusted for SOL
		
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 9
        formatter.minimumFractionDigits = 0
        formatter.groupingSeparator = ""
        formatter.decimalSeparator = "."
        return formatter.string(from: NSNumber(value: balanceSOL))
    }
	
    private let rpcURL = URL(string: Endpoint.solanaServiceAlchemyRpc)!
    private let jsonDecoder = JSONDecoder()
	
    func sendSolanaTransaction(encodedTransaction: String) async {
        do {
            let requestBody: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sendTransaction",
                "params": [encodedTransaction]
            ]
            let data = try await postRequest(with: requestBody)
            let response = try jsonDecoder.decode(SolanaRPCResponse<String>.self, from: data)
            self.transactionResult = response.result
			
        } catch {
            print("Error sending transaction: \(error.localizedDescription)")
        }
    }
	
    func getSolanaBalance(tx: SendTransaction) async {
        do {
            let requestBody: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "getBalance",
                "params": [tx.fromAddress]
            ]
            let data = try await postRequest(with: requestBody)
            let response = try jsonDecoder.decode(SolanaRPCResponse<SolanaBalanceResponse>.self, from: data)
            self.balance = response.result.value
            tx.coin.rawBalance = "\(response.result.value)"
            if let priceRateUsd = CryptoPriceService.shared.cryptoPrices?.prices[Chain.Solana.name.lowercased()]?["usd"] {
                tx.coin.priceRate = priceRateUsd
            }
        } catch {
            print("Error fetching balance: \(error.localizedDescription)")
        }
    }
	
    func fetchRecentBlockhash() async {
        do {
            let requestBody: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "getRecentBlockhash",
                "params": [["commitment": "finalized"]]
            ]
			
            let data = try await postRequest(with: requestBody)
            let response = try jsonDecoder.decode(SolanaRPCResponse<SolanaRecentBlockhashResponse>.self, from: data)
			
            self.recentBlockHash = response.result.value.blockhash
            self.feeInLamports = String(response.result.value.feeCalculator.lamportsPerSignature)            
        } catch {
            print("Error fetching recent blockhash: \(error.localizedDescription)")
        }
    }
	
    private func postRequest(with body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
		
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }
}
