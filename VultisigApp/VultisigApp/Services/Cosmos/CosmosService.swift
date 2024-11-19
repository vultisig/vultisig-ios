import Foundation

class CosmosService {
    
    func fetchBalances(coin: Coin) async throws -> [CosmosBalance] {
        
        if coin.isNativeToken || (!coin.isNativeToken && coin.contractAddress.contains("ibc/")) || (!coin.isNativeToken && !coin.contractAddress.contains("terra")) {
            
            guard let url = balanceURL(forAddress: coin.address) else {
                return [CosmosBalance]()
            }
            
            let (data, _) = try await URLSession.shared.data(from: url)
            let balanceResponse = try JSONDecoder().decode(CosmosBalanceResponse.self, from: data)
            return balanceResponse.balances
            
        } else {
            
            let balance = try await fetchWasmTokenBalances(coin: coin)
            return [CosmosBalance(denom: coin.contractAddress, amount: balance)]
            
        }
        
    }
    
    func fetchIbcDenomTraces(coin: Coin) async -> CosmosIbcDenomTraceDenomTrace? {
        guard let url = ibcDenomTraceURL(coin: coin) else {
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            let decoder = JSONDecoder()
            let response = try decoder.decode(CosmosIbcDenomTrace.self, from: data)
            
            if let denomTrace = response.denomTrace {
                // Handle successful response
                print("Path: \(denomTrace.path)")
                print("Base Denom: \(denomTrace.baseDenom)")
                return denomTrace
            } else if let error = response.error {
                // Handle "not implemented" error
                print("Error Code: \(error.code)")
                print("Error Message: \(error.message)")
            } else if let code = response.code, let message = response.message {
                // Handle general error
                print("Error Code: \(code)")
                print("Error Message: \(message)")
                if let details = response.details {
                    print("Details: \(details)")
                }
            } else {
                // Handle unexpected response
                print("Unexpected response format.")
            }
            
            return nil
        } catch {
            print("An error occurred: \(error)")
            // Return nil in case of any error
            return nil
        }
    }
    
    func fetchWasmTokenBalances(coin: Coin) async throws -> String {
        
        let payload = "{\"balance\":{\"address\":\"\(coin.address)\"}}"
        let base64Payload = payload.data(using: .utf8)?.base64EncodedString()
        
        guard let base64Payload else {
            return "0"
        }
        
        guard let url = wasmTokenBalanceURL(contractAddress: coin.contractAddress, base64Payload: base64Payload) else {
            return "0"
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        if let balance = Utils.extractResultFromJson(fromData: data, path: "data.balance") as? String {
            return balance
        }
        
        return "0"
    }
        
    func fetchLatestBlock(coin: Coin) async throws -> String {
        
        guard let url = latestBlockURL(coin: coin) else {
            return "0"
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        if let block = Utils.extractResultFromJson(fromData: data, path: "block.header.height") as? String {
            return block
        }
        
        return "0"
    }
    
    func fetchAccountNumber(_ address: String) async throws -> CosmosAccountValue? {
        guard let url = accountNumberURL(forAddress: address) else {
            return nil
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let accountResponse = try JSONDecoder().decode(CosmosAccountsResponse.self, from: data)
        return accountResponse.account
    }
    
    func broadcastTransaction(jsonString: String) async -> Result<String, Error> {
        guard let url = transactionURL(), let jsonData = jsonString.data(using: .utf8) else {
            return .failure(HelperError.runtimeError("Failed to convert input json to data"))
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let (data, resp) = try await URLSession.shared.data(for: request)
            guard let httpResponse = resp as? HTTPURLResponse else {
                return .failure(HelperError.runtimeError("Invalid HTTP response"))
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                return .failure(HelperError.runtimeError("Status code: \(httpResponse.statusCode), \(String(data: data, encoding: .utf8) ?? "Unknown error")"))
            }
            let response = try JSONDecoder().decode(CosmosTransactionBroadcastResponse.self, from: data)
            if let code = response.txResponse?.code, code == 0 || code == 19 {
                if let txHash = response.txResponse?.txhash {
                    return .success(txHash)
                }
            }
            return .failure(HelperError.runtimeError(String(data: data, encoding: .utf8) ?? "Unknown error"))
            
        } catch {
            return .failure(error)
        }
    }
    
    // Methods to be overridden
    func balanceURL(forAddress address: String) -> URL? {
        fatalError("Must override in subclass")
    }
    
    func accountNumberURL(forAddress address: String) -> URL? {
        fatalError("Must override in subclass")
    }
    
    func transactionURL() -> URL? {
        fatalError("Must override in subclass")
    }
    
    func wasmTokenBalanceURL(contractAddress: String, base64Payload: String) -> URL? {
        fatalError("Must override in subclass")
    }
    
    func ibcDenomTraceURL(coin: Coin)-> URL? {
        fatalError("Must override in subclass")
    }
    
    func latestBlockURL(coin: Coin)-> URL? {
        fatalError("Must override in subclass")
    }
}
