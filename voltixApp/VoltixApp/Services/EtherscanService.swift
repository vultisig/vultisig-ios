import SwiftUI

@MainActor
public class EtherScanService: ObservableObject {
    @Published var transactionHash: String?
    @Published var errorMessage: String?
    @Published var transactions: [TransactionDetail]? = []
    @Published var addressFor: String?
    
    struct BroadcastResponse: Decodable, CustomStringConvertible {
        let id: Int
        let jsonrpc: String
        let result: String // This will hold the transaction hash
        
        var description: String {
            return "BroadcastResponse(id: \(id), jsonrpc: \(jsonrpc), result: \(result))"
        }
    }
    
    public enum EtherScanError: Error {
        case invalidURL
        case httpError(Int, String) // Includes HTTP status code and message
        case apiError(String)
        case unexpectedResponse
        case decodingError(String)
        case unknown(Error)
    }
    
    public func broadcastTransaction(hex: String, apiKey: String) async {
        let urlString = "https://api.etherscan.io/api?module=proxy&action=eth_sendRawTransaction&hex=\(hex)&apikey=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            self.errorMessage = "Invalid URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST" // The method is POST, parameters are included in the URL
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let responseString = String(data: data, encoding: .utf8) ?? "No response body"
                print("HTTP Error: \(statusCode) - \(responseString)")
                throw EtherScanError.httpError(statusCode, "HTTP Error: \(statusCode) - \(responseString)")
            }
            
            print(String(data: data, encoding: .utf8) ?? "No response body")
            
            let decoder = JSONDecoder()
            let broadcastResponse = try decoder.decode(BroadcastResponse.self, from: data)
            
            DispatchQueue.main.async {
                
                print("ETHER BROADCAST: \(broadcastResponse.result)")
                print(broadcastResponse)
                self.transactionHash = broadcastResponse.result
            }
        } catch {
            DispatchQueue.main.async {
                if let decodingError = error as? DecodingError {
                    self.errorMessage = "Decoding error: \(decodingError.localizedDescription)"
                } else if let etherScanError = error as? EtherScanError {
                    switch etherScanError {
                        case .httpError(let statusCode, let message):
                            self.errorMessage = "HTTP Error \(statusCode): \(message)"
                        case .apiError(let message):
                            self.errorMessage = message
                        default:
                            self.errorMessage = "Error: \(error.localizedDescription)"
                    }
                } else {
                    self.errorMessage = "Unknown error: \(error.localizedDescription)"
                }
                print(self.errorMessage)
            }
        }
    }
    
    struct EtherscanAPIResponse: Codable {
        let status: String
        let message: String
        let result: [TransactionDetail]?
    }
    
    struct TransactionDetail: Codable {
        let blockNumber: String?
        let timeStamp: String?
        let hash: String?
        let nonce: String?
        let blockHash: String?
        let transactionIndex: String?
        let from: String
        let to: String
        let value: String
        let gas: String
        let gasPrice: String
        let isError: String?
        let txreceipt_status: String?
        let input: String?
        let contractAddress: String?
        let cumulativeGasUsed: String?
        let gasUsed: String?
        let confirmations: String?
        
        // Fields that might not exist in all responses, now optional
        let methodId: String?
        let functionName: String?
        
        // Added properties for ERC20, already optional
        let tokenName: String?
        let tokenSymbol: String?
        let tokenDecimal: String?
    }
    
    func fetchTransactions(forAddress address: String, apiKey: String) async {
        let urlString = "https://api.etherscan.io/api?module=account&action=txlist&address=\(address)&startblock=0&endblock=99999999&sort=asc&apikey=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            self.errorMessage = "Invalid URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let responseString = String(data: data, encoding: .utf8) ?? "No response body"
                throw EtherScanError.httpError(statusCode, "HTTP Error: \(statusCode) - \(responseString)")
            }
            
            let decodedResponse = try JSONDecoder().decode(EtherscanAPIResponse.self, from: data)
            
            DispatchQueue.main.async {
                self.transactions = decodedResponse.result ?? []
                self.addressFor = address
            }
        } catch {
            DispatchQueue.main.async {
                self.handleError(error: error)
            }
        }
    }
    
    func fetchERC20Transactions(forAddress address: String, apiKey: String, contractAddress: String) async {
        
        let urlString = "https://api.etherscan.io/api?module=account&action=tokentx&contractaddress=\(contractAddress)&address=\(address)&startblock=0&endblock=99999999&sort=asc&apikey=\(apiKey)"

        guard let url = URL(string: urlString) else {
            self.errorMessage = "Invalid URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        print(urlString)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let responseString = String(data: data, encoding: .utf8) ?? "No response body"
                throw EtherScanError.httpError(statusCode, "HTTP Error: \(statusCode) - \(responseString)")
            }
            
            let decodedResponse = try JSONDecoder().decode(EtherscanAPIResponse.self, from: data)
            
            DispatchQueue.main.async {
                self.transactions = decodedResponse.result ?? []
                self.addressFor = address
            }
        } catch {
            DispatchQueue.main.async {
                self.handleError(error: error)
                print(error)
            }
        }
    }
    
    private func handleError(error: Error) {
        if let decodingError = error as? DecodingError {
            self.errorMessage = "Decoding error: \(decodingError.localizedDescription)"
        } else if let etherScanError = error as? EtherScanError {
            switch etherScanError {
                case .httpError(let statusCode, let message):
                    self.errorMessage = "HTTP Error \(statusCode): \(message)"
                case .apiError(let message):
                    self.errorMessage = message
                default:
                    self.errorMessage = "Error: \(error.localizedDescription)"
            }
        } else {
            self.errorMessage = "Unknown error: \(error.localizedDescription)"
        }
    }
}
