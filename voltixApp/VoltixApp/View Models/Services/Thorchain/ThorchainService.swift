    //
    //  ThorchainService.swift
    //  VoltixApp
    //
    //  Created by Enrique Souza Soares on 06/03/2024.
    //

import Foundation

fileprivate struct BalanceCacheEntry: Codable {
    let balances: [ThorchainBalance]
    let timestamp: Date
}

fileprivate struct AccountCacheEntry: Codable {
    let accountNumber: String
    let timestamp: Date
}

class ThorchainService: ObservableObject {
    static let shared = ThorchainService()
    
    @Published var balances: [ThorchainBalance]?
    @Published var errorMessage: String?
    @Published var accountNumber: String?
    
    private init() {}
    
    func fetchBalances(_ address: String) async {
            // Attempt to load cached balances if they are still valid
        if let cachedBalances = loadBalancesFromCache(forAddress: address) {
            DispatchQueue.main.async {
                self.balances = cachedBalances
            }
            return
        }
        
        guard let url = URL(string: "https://thornode.ninerealms.com/cosmos/bank/v1beta1/balances/\(address)") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            let balanceResponse = try JSONDecoder().decode(ThorchainBalanceResponse.self, from: data)
            DispatchQueue.main.async {
                self.balances = balanceResponse.balances
                self.cacheBalances(balanceResponse.balances, forAddress: address)
            }
        } catch {
            DispatchQueue.main.async {
                self.handleDecodingError(error)
            }
        }
    }
    
    func fetchAccountNumber(_ address: String) async {
        if let cachedAccountNumber = loadAccountNumberFromCache(forAddress: address) {
            DispatchQueue.main.async {
                self.accountNumber = cachedAccountNumber
            }
            return
        }
        
        guard let url = URL(string: "https://thornode.ninerealms.com/cosmos/auth/v1beta1/accounts/\(address)") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let accountResponse = try JSONDecoder().decode(ThorchainAccountNumberResponse.self, from: data)
            DispatchQueue.main.async {
                self.accountNumber = accountResponse.result.value.accountNumber
                self.cacheAccountNumber(accountResponse.result.value.accountNumber, forAddress: address)
            }
        } catch {
            DispatchQueue.main.async {
                self.handleDecodingError(error)
            }
        }
    }
    
    private func handleDecodingError(_ error: Error) {
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
    }
    
    private func cacheBalances(_ balances: [ThorchainBalance], forAddress address: String) {
        let addressKey = "balancesCache_\(address)"
        let cacheEntry = BalanceCacheEntry(balances: balances, timestamp: Date())
        
        if let encodedData = try? JSONEncoder().encode(cacheEntry) {
            UserDefaults.standard.set(encodedData, forKey: addressKey)
        }
    }
    
    private func loadBalancesFromCache(forAddress address: String) -> [ThorchainBalance]? {
        let addressKey = "balancesCache_\(address)"
        
        guard let savedData = UserDefaults.standard.object(forKey: addressKey) as? Data,
              let cacheEntry = try? JSONDecoder().decode(BalanceCacheEntry.self, from: savedData),
              -cacheEntry.timestamp.timeIntervalSinceNow < 60 else { // Checks if the cache is older than 1 minute
            return nil
        }
        
        return cacheEntry.balances
    }
    
    private func cacheAccountNumber(_ accountNumber: String, forAddress address: String) {
        let addressKey = "ThorchainAccountNumberCache_\(address)"
        let cacheEntry = AccountCacheEntry(accountNumber: accountNumber, timestamp: Date())
        
        if let encodedData = try? JSONEncoder().encode(cacheEntry) {
            UserDefaults.standard.set(encodedData, forKey: addressKey)
        }
    }
    
    private func loadAccountNumberFromCache(forAddress address: String) -> String? {
        let addressKey = "ThorchainAccountNumberCache_\(address)"
        
        guard let savedData = UserDefaults.standard.object(forKey: addressKey) as? Data,
              let cacheEntry = try? JSONDecoder().decode(AccountCacheEntry.self, from: savedData),
              -cacheEntry.timestamp.timeIntervalSinceNow < 86400 else { // 24 hours in seconds
            return nil
        }
        
        return cacheEntry.accountNumber
    }
}
