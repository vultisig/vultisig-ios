//
//  ThorchainService.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 06/03/2024.
//

import Foundation

class ThorchainService {
    static let shared = ThorchainService()
    
    private init() {}
    
    func fetchBalances(_ address: String) async throws -> [ThorchainBalance] {
        let cachedBalances = loadBalancesFromCache(forAddress: address)
        if cachedBalances.count > 0 {
            return cachedBalances
        }
        guard let url = URL(string: Endpoint.fetchAccountBalanceThorchainNineRealms(address: address)) else        {
            return [ThorchainBalance]()
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let balanceResponse = try JSONDecoder().decode(ThorchainBalanceResponse.self, from: data)
        self.cacheBalances(balanceResponse.balances, forAddress: address)
        return balanceResponse.balances
    }
    
    func fetchAccountNumber(_ address: String) async throws -> ThorchainAccountValue? {
        guard let url = URL(string: Endpoint.fetchAccountNumberThorchainNineRealms(address)) else {
            return nil
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let accountResponse = try JSONDecoder().decode(ThorchainAccountNumberResponse.self, from: data)
        return accountResponse.result.value
    }
    
    private func cacheBalances(_ balances: [ThorchainBalance], forAddress address: String) {
        let addressKey = "balancesCache_\(address)"
        let cacheEntry = BalanceCacheEntry(balances: balances, timestamp: Date())
        
        if let encodedData = try? JSONEncoder().encode(cacheEntry) {
            UserDefaults.standard.set(encodedData, forKey: addressKey)
        }
    }
    
    private func loadBalancesFromCache(forAddress address: String) -> [ThorchainBalance] {
        let addressKey = "balancesCache_\(address)"
        
        guard let savedData = UserDefaults.standard.object(forKey: addressKey) as? Data,
              let cacheEntry = try? JSONDecoder().decode(BalanceCacheEntry.self, from: savedData),
              -cacheEntry.timestamp.timeIntervalSinceNow < 60
        else { // Checks if the cache is older than 1 minute
            return [ThorchainBalance]()
        }
        
        return cacheEntry.balances
    }
}
