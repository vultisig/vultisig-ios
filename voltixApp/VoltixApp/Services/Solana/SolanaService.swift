import Foundation
import SwiftUI

class SolanaService {
    static let shared = SolanaService()
    private init() {}
    
    func solBalanceInFiat(balance: String, price: Double?, includeCurrencySymbol: Bool = true) -> String? {
        guard let fiatPrice = price else { return nil }
        
        let balanceSOL = Decimal(string:balance) ?? 0 / 1_000_000_000
        let balanceFiat = balanceSOL * Decimal(fiatPrice)
        
        return balanceFiat.formatToFiat()
    }
    
    func formattedSolBalance(balance: String?) -> String? {
        guard let solAmountInt = balance else {
            return "Balance not available"
        }
        
        let solAmount = Decimal(string:solAmountInt) ?? 0
        let balanceSOL = solAmount / 1_000_000_000.0 // Adjusted for SOL
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 9
        formatter.minimumFractionDigits = 0
        formatter.groupingSeparator = ""
        formatter.decimalSeparator = "."
        return formatter.string(from: balanceSOL as NSNumber)
    }
    
    private let rpcURL = URL(string: Endpoint.solanaServiceAlchemyRpc)!
    private let jsonDecoder = JSONDecoder()
    
    func sendSolanaTransaction(encodedTransaction: String) async -> String? {
        do {
            let requestBody: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sendTransaction",
                "params": [encodedTransaction]
            ]
            let data = try await postRequest(with: requestBody)
            let response = try jsonDecoder.decode(SolanaRPCResponse<String>.self, from: data)
            return response.result
            
        } catch {
            print("Error sending transaction: \(error.localizedDescription)")
        }
        return nil
    }
    
    func getSolanaBalance(coin: Coin) async throws -> (rawBalance: String, priceRate: Double){
        var rawBalance = "0"
        let priceRateFiat = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
        
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getBalance",
            "params": [coin.address]
        ]
        do {
            let data = try await postRequest(with: requestBody)
            let response = try jsonDecoder.decode(SolanaRPCResponse<SolanaBalanceResponse>.self, from: data)
            rawBalance = "\(response.result.value)"
        } catch {
            print("Error fetching balance: \(error.localizedDescription)")
            throw error
        }
        return (rawBalance,priceRateFiat)
    }
    
    func fetchRecentBlockhash() async throws -> (recentBlockHash: String?, feeInLamports: String) {
        var blockHash: String? = nil
        let feeInLamports = "7000"
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getLatestBlockhash",
            "params": [["commitment": "finalized"]]
        ]
        do {
            let data = try await postRequest(with: requestBody)
            blockHash = Utils.extractResultFromJson(fromData: data, path: "result.value.blockhash") as? String
        } catch {
            print("Error fetching recent blockhash: \(error.localizedDescription)")
            throw error
        }
        return (blockHash,feeInLamports)
    }
    
    // The implementation follows this example.
    // https://docs.chainstack.com/docs/solana-estimate-priority-fees-getrecentprioritizationfees
    func fetchAndCalculatePrioritizationFees(account: String) async throws -> (averageFeeIncludingZeros: Int, averageFeeExcludingZeros: Int, medianFee: Int, highPriorityFee: Int) {
        
        struct PrioritizationFeeResponse: Decodable {
            let result: [FeeObject]
        }
        
        struct FeeObject: Decodable {
            let prioritizationFee: Int
            let slot: Int
        }
        
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getRecentPrioritizationFees",
            "params": [[account]]
        ]
        
        let data = try await postRequest(with: requestBody)
        let decoder = JSONDecoder()
        let response = try decoder.decode(PrioritizationFeeResponse.self, from: data)
        
        let fees = response.result.map { $0.prioritizationFee }
        let averageFeeIncludingZeros = fees.reduce(0, +) / fees.count
        
        let nonZeroFees = fees.filter { $0 > 0 }
        let averageFeeExcludingZeros = nonZeroFees.isEmpty ? 0 : nonZeroFees.reduce(0, +) / nonZeroFees.count
        
        let sortedNonZeroFees = nonZeroFees.sorted()
        let medianFee: Int
        if sortedNonZeroFees.isEmpty {
            medianFee = 0
        } else if sortedNonZeroFees.count % 2 == 0 {
            let midIndex = sortedNonZeroFees.count / 2
            medianFee = (sortedNonZeroFees[midIndex - 1] + sortedNonZeroFees[midIndex]) / 2
        } else {
            medianFee = sortedNonZeroFees[sortedNonZeroFees.count / 2]
        }
        
        // Calculate the high priority fee
        let highPriorityFee = nonZeroFees.max() ?? 0
        
        return (averageFeeIncludingZeros, averageFeeExcludingZeros, medianFee, highPriorityFee)
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
