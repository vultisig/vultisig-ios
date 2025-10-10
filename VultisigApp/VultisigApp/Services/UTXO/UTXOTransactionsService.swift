import SwiftUI
import WalletCore

enum UTXOTransactionError: Error {
    case invalidURL
    case httpError(Int) // Includes the HTTP status code
    case apiError(String) // Error message from the API
    case unexpectedResponse
    case unknown(Error) // Wraps an unknown error
}
public class UTXOTransactionsService: ObservableObject {
    @Published var walletData: [UTXOTransactionMempool]?
    @Published var errorMessage: String?
    
    // Cache structure to hold data and timestamp
    private struct CacheEntry {
        let data: [UTXOTransactionMempool]
        let timestamp: Date
    }
    
    // Dictionary to store cache entries with userAddress as the key
    private var cache: [String: CacheEntry] = [:]
    
    // Function to check if cache for a given userAddress is valid (not older than 5 minutes)
    private func isCacheValid(for userAddress: String) -> Bool {
        if let entry = cache[userAddress], -entry.timestamp.timeIntervalSinceNow < 300 {
            return true // Cache is valid if less than 5 minutes old
        }
        return false
    }
    
    func fetchTransactions(_ userAddress: String, endpointUrl: String) async {
        // Use cache if it's valid for the requested userAddress
        if isCacheValid(for: userAddress), let cachedData = cache[userAddress]?.data {
            walletData = cachedData
            return
        }
        
        guard let url = URL(string: endpointUrl) else {
            errorMessage = "Invalid URL"
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            let decodedData = try decoder.decode([UTXOTransactionMempool].self, from: data)
            let updatedData = decodedData.map { transaction in
                UTXOTransactionMempool(txid: transaction.txid, version: transaction.version, locktime: transaction.locktime, vin: transaction.vin, vout: transaction.vout, fee: transaction.fee, status: transaction.status, userAddress: userAddress)
            }
            
            cache[userAddress] = CacheEntry(data: updatedData, timestamp: Date())
            walletData = updatedData
        } catch {
            errorMessage = Utils.handleJsonDecodingError(error)
        }
    }
    
    

    // Currently there is a bug in Blockchair API that broadcasting Bitcoin transactions sometimes doesn't sync with bitcoin network
    public static func broadcastBitcoinTransaction(signedTransaction: String,completion: @escaping (Result<String, Error>) -> Void){
        let url = Endpoint.bitcoinBroadcast()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = signedTransaction.data(using: .utf8)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            func finish(_ result: Result<String, Error>) {
                DispatchQueue.main.async {
                    completion(result)
                }
            }
            if let data = data, let txid = String(data: data, encoding: .utf8) {
                finish(.success(txid))
            } else if let error = error {
                finish(.failure(error))
            }
        }
        task.resume()
    }
    
    public static func broadcastTransaction(chain: String, signedTransaction: String, completion: @escaping (Result<String, Error>) -> Void) {
        let url = Endpoint.blockchairBroadcast(chain.lowercased())
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let postData: [String: Any] = ["data": signedTransaction]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: postData, options: []) else {
            completion(.failure(NSError(domain: "BlockchairServiceError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize data"])))
            return
        }
        request.httpBody = httpBody
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            func finish(_ result: Result<String, Error>) {
                DispatchQueue.main.async {
                    completion(result)
                }
            }
            if let error = error {
                finish(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                finish(.failure(NSError(domain: "BlockchairServiceError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid response received"])))
                return
            }
            
            if httpResponse.statusCode == 200, let jsonData = data {
                do {
                    if let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
                       let transactionData = json["data"] as? [String: Any],
                       let transactionHash = transactionData["transaction_hash"] as? String
                    {
                        finish(.success(transactionHash))
                    } else {
                        finish(.failure(NSError(domain: "BlockchairServiceError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unexpected response format"])))
                    }
                } catch {
                    finish(.failure(error))
                }
            } else if httpResponse.statusCode == 400, let jsonData = data {
                do {
                    if let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
                       let context = json["context"] as? [String: Any],
                       let errorDescription = context["error"] as? String
                    {
                        finish(.failure(NSError(domain: "BlockchairServiceError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to broadcast transaction. Error: \(errorDescription)"])))
                    }
                } catch {
                    finish(.failure(error))
                }
            } else {
                finish(.failure(NSError(domain: "BlockchairServiceError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Received HTTP \(httpResponse.statusCode)"])))
            }
        }
        
        task.resume()
    }
    
    func getAmount(for transaction: UTXOTransactionMempool, tx: SendTransaction) -> String {
        if transaction.isSent {
            return formatAmount(transaction.amountSent, tx: tx)
        } else if transaction.isReceived {
            return formatAmount(transaction.amountReceived, tx: tx)
        }
        return ""
    }
    
    func formatAmount(_ amountSatoshis: Int, tx: SendTransaction) -> String {
        let amountBTC = Decimal(amountSatoshis) / 100_000_000 // Convert satoshis to BTC
        return  amountBTC.formatForDisplay()
    }
    
    /// Calculate transaction fee using WalletCore's exact logic
    /// 
    /// **WalletCore Reference:**
    /// - File: `src/Bitcoin/TransactionBuilder.cpp`
    /// - Lines: ~108-120 (output_size = 2 + extraOutputs for normal transactions)
    /// - Lines: ~167-184 (fee calculation formulas)
    /// 
    /// - Parameters:
    ///   - inputs: Number of UTXO inputs
    ///   - byteFee: Fee rate in sats per byte
    ///   - chain: The blockchain chain type
    /// - Returns: Calculated fee in sats
    static func calculateTransactionFee(inputs: Int, byteFee: Int64, chain: String) -> Int64 {
        // WalletCore uses 2 outputs by default (1 main + 1 change) for fee estimation
        // Source: src/Bitcoin/TransactionBuilder.cpp:108-120
        // Comment: "we use a max amount of transaction outputs to simplify the algorithm"
        let outputs = 2
        let estimatedTxSize: Double
        
        switch chain.lowercased() {
        case "bitcoin", "bitcoincash", "litecoin":
            // SegWit calculation from WalletCore
            // Source: src/Bitcoin/FeeCalculator.cpp:15-25
            // Constants: gSegwitBytesPerInput = 101.25, gSegwitBytesPerOutput = 31, gDefaultBytesBase = 10
            estimatedTxSize = Double(inputs) * 101.25 + Double(outputs) * 31.0 + 10.0
        case "dogecoin", "dash":
            // Legacy calculation from WalletCore  
            // Source: src/Bitcoin/FeeCalculator.cpp:15-25
            // Constants: gDefaultBytesPerInput = 148, gDefaultBytesPerOutput = 34, gDefaultBytesBase = 10
            estimatedTxSize = Double(inputs) * 148.0 + Double(outputs) * 34.0 + 10.0
        default:
            // Default to legacy calculation (same as WalletCore fallback)
            estimatedTxSize = Double(inputs) * 148.0 + Double(outputs) * 34.0 + 10.0
        }
        
        let txSize = Int64(ceil(estimatedTxSize))
        return txSize * byteFee
    }
    
    /// Estimate how many UTXOs will be needed for a given amount using WalletCore's approach
    /// 
    /// **WalletCore Reference:**
    /// - File: `src/Bitcoin/InputSelector.cpp`
    /// - Lines: ~140-200 (InputSelector::select method)
    /// - Logic: WalletCore iterates from 1 input up to N inputs, calculating fee for each iteration
    /// - Formula: targetWithFee = targetValue + feeCalculator.calculate(numInputs, numOutputs, byteFee)
    /// 
    /// - Parameters:
    ///   - amount: Amount in sats
    ///   - chain: The blockchain chain type
    /// - Returns: Estimated number of UTXOs needed
    static func estimateUTXOInputs(amount: Int64, chain: String) -> Int {
        // WalletCore's approach: try increasing numbers of inputs until fee + amount is reasonable
        // Source: src/Bitcoin/InputSelector.cpp:140-200
        
        // Assume average UTXO size for estimation (WalletCore uses actual UTXOs, we estimate)
        let averageUTXOSize: Int64
        switch chain.lowercased() {
        case "bitcoin", "bitcoincash", "litecoin":
            averageUTXOSize = 500_000 // ~0.005 BTC average UTXO
        case "dogecoin":
            averageUTXOSize = 50_000_000_000 // ~50 DOGE average UTXO  
        case "dash":
            averageUTXOSize = 10_000_000 // ~0.1 DASH average UTXO
        default:
            averageUTXOSize = 1_000_000 // Default 0.01 unit
        }
        
        // WalletCore iterates from 1 to N inputs, we simulate this
        for numInputs in 1...10 { // Max 10 inputs for estimation
            let estimatedUTXOValue = Int64(numInputs) * averageUTXOSize
            let estimatedFee = calculateTransactionFee(inputs: numInputs, byteFee: 10, chain: chain) // Use low byteFee for estimation
            
            if estimatedUTXOValue >= amount + estimatedFee {
                return numInputs
            }
        }
        
        // Fallback: if amount is very large, return reasonable estimate
        return min(10, max(1, Int(amount / averageUTXOSize) + 1))
    }
}
