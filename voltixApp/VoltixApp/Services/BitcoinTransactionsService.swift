import SwiftUI

@MainActor
public class BitcoinTransactionsService: ObservableObject {
    @Published var walletData: [BitcoinTransactionMempool]?
    @Published var errorMessage: String?
    
    func fetchTransactions(_ userAddress: String) async {
        
        print("https://mempool.space/api/address/\(userAddress)/txs")
        
        guard let url = URL(string: "https://mempool.space/api/address/\(userAddress)/txs") else {
            errorMessage = "Invalid URL"
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            let decodedData = try decoder.decode([BitcoinTransactionMempool].self, from: data)
            
            self.walletData = decodedData.map { transaction in
                BitcoinTransactionMempool(txid: transaction.txid, version: transaction.version, locktime: transaction.locktime, vin: transaction.vin, vout: transaction.vout, fee: transaction.fee, status: transaction.status, userAddress: userAddress)
            }
        } catch let DecodingError.dataCorrupted(context) {
            print(context)
        } catch let DecodingError.keyNotFound(key, context) {
            print("Key '\(key)' not found:", context.debugDescription)
            print("codingPath:", context.codingPath)
        } catch let DecodingError.valueNotFound(value, context) {
            print("Value '\(value)' not found:", context.debugDescription)
            print("codingPath:", context.codingPath)
        } catch let DecodingError.typeMismatch(type, context)  {
            print("Type '\(type)' mismatch:", context.debugDescription)
            print("codingPath:", context.codingPath)
        } catch {
            print("error: ", error)
        }
    }
    
    enum BitcoinTransactionError: Error {
        case invalidURL
        case httpError(Int) // Includes the HTTP status code
        case apiError(String) // Error message from the API
        case unexpectedResponse
        case unknown(Error) // Wraps an unknown error
    }
    
    
    public static func broadcastTransaction(_ rawTransaction: String) async throws -> String {
        let urlString = "https://mempool.space/api/tx"
        guard let url = URL(string: urlString) else {
            throw BitcoinTransactionError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = rawTransaction.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BitcoinTransactionError.unexpectedResponse
            }
            
            let responseString = String(data: data, encoding: .utf8) ?? ""
            
            if httpResponse.statusCode == 200 {
                    // Success, return txid
                return responseString
            } else {
                    // Attempt to handle as plain-text error message
                if httpResponse.statusCode == 400, // Or other relevant status codes
                   !responseString.isEmpty {
                        // Here you could also attempt to parse the responseString if it's JSON formatted
                    throw BitcoinTransactionError.apiError(responseString)
                } else {
                    throw BitcoinTransactionError.httpError(httpResponse.statusCode)
                }
            }
        } catch {
            throw BitcoinTransactionError.unknown(error)
        }
    }
}
