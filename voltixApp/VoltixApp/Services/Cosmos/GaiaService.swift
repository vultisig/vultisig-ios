//
//  GaiaService.swift
//  VoltixApp
//
//  Created by Johnny Luo on 1/4/2024.
//

import Foundation

class GaiaService{
    static let shared = GaiaService()
    private init(){}

    func fetchBalances(_ address: String) async throws -> [CosmosBalance] {
        let cachedBalances = loadBalancesFromCache(forAddress: address)
        if cachedBalances.count > 0 {
            return cachedBalances
        }
        guard let url = URL(string: Endpoint.fetchCosmosAccountBalance(address: address)) else        {
            return [CosmosBalance]()
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let balanceResponse = try JSONDecoder().decode(CosmosBalanceResponse.self, from: data)
        self.cacheBalances(balanceResponse.balances, forAddress: address)
        return balanceResponse.balances
    }
    func fetchAccountNumber(_ address: String) async throws -> CosmosAccountValue? {
        guard let url = URL(string: Endpoint.fetchCosmosAccountNumber(address)) else {
            return nil
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let accountResponse = try JSONDecoder().decode(CosmosAccountNumberResponse.self, from: data)
        return accountResponse.result.value
    }
    
    private func cacheBalances(_ balances: [CosmosBalance], forAddress address: String) {
        let addressKey = "balancesCache_\(address)"
        let cacheEntry = BalanceCacheEntry(balances: balances, timestamp: Date())
        
        if let encodedData = try? JSONEncoder().encode(cacheEntry) {
            UserDefaults.standard.set(encodedData, forKey: addressKey)
        }
    }
    
    private func loadBalancesFromCache(forAddress address: String) -> [CosmosBalance] {
        let addressKey = "balancesCache_\(address)"
        
        guard let savedData = UserDefaults.standard.object(forKey: addressKey) as? Data,
              let cacheEntry = try? JSONDecoder().decode(BalanceCacheEntry.self, from: savedData),
              -cacheEntry.timestamp.timeIntervalSinceNow < 60
        else { // Checks if the cache is older than 1 minute
            return [CosmosBalance]()
        }
        
        return cacheEntry.balances
    }
    func broadcastTransaction(jsonString: String) async -> Result<String,Error> {
        let url = URL(string: Endpoint.broadcastCosmosTransaction)!
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            return .failure(HelperError.runtimeError("fail to convert input json to data"))
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        do{
            let (data,resp)  =  try await URLSession.shared.data(for: request)
            guard let httpResponse = resp as? HTTPURLResponse else {
                return .failure(HelperError.runtimeError("Invalid http response"))
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                return .failure(HelperError.runtimeError("status code:\(httpResponse.statusCode), \(String(data: data, encoding: .utf8) ?? "Unknown error")"))
            }
            let response = try JSONDecoder().decode(CosmosTransactionBroadcastResponse.self, from: data)
            // Check if the transaction was successful based on the `code` field
            // code 19 means the transaction has been exist in the mempool , which indicate another party already broadcast successfully
            if let code = response.txResponse?.code, code == 0 || code == 19 {
                // Transaction successful
                if let txHash = response.txResponse?.txhash {
                    return .success(txHash)
                }
            }
            return .failure(HelperError.runtimeError(String(data: data, encoding: .utf8) ?? "Unknown error"))
            
        }
        catch{
            return .failure(error)
        }
        
    }
}
