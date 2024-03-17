import SwiftUI

enum EtherScanError: Error {
    case invalidURL
    case httpError(Int, String) // Includes HTTP status code and message
    case apiError(String)
    case unexpectedResponse
    case decodingError(String)
    case unknown(Error)
}

@MainActor
public class EtherScanService: ObservableObject {
    @Published var transactionHash: String?
    @Published var errorMessage: String?
    @Published var transactions: [EtherscanAPITransactionDetail]? = []
    @Published var addressFor: String?
    
    public func broadcastTransaction(hex: String) async {
        let urlString = Endpoint.broadcastEtherscanTransaction(hex: hex)
        
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
            
            // print(String(data: data, encoding: .utf8) ?? "No response body")
            
            let decoder = JSONDecoder()
            let broadcastResponse = try decoder.decode(EtherscanBroadcastResponse.self, from: data)
            
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
                
                print(String(describing: self.errorMessage))
            }
        }
    }
    
    func fetchTransactions(forAddress address: String) async {
        let urlString = Endpoint.fetchEtherscanTransactions(address: address)
        
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
    
    func fetchERC20Transactions(forAddress address: String, contractAddress: String) async {
        let urlString = Endpoint.fetchERC20Transactions(address: address, contractAddress: contractAddress)
        
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
