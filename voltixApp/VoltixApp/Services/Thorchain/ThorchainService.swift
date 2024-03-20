//
//  ThorchainService.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 06/03/2024.
//

import Foundation

private struct BalanceCacheEntry: Codable {
    let balances: [ThorchainBalance]
    let timestamp: Date
}

@MainActor
class ThorchainService: ObservableObject {
    static let shared = ThorchainService()
    
    @Published var balances: [ThorchainBalance]?
    @Published var errorMessage: String?
    @Published var account: ThorchainAccountValue?
    
    func runeBalanceInUSD(usdPrice: Double?, includeCurrencySymbol: Bool = true) -> String? {
        guard let usdPrice = usdPrice,
              let runeBalanceString = runeBalance,
              let runeAmount = Double(runeBalanceString) else { return nil }
        
        let balanceRune = runeAmount / 100_000_000.0
        let balanceUSD = balanceRune * usdPrice
        
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
    
    var formattedRuneBalance: String? {
        guard let balances = balances else { return nil }
        for balance in balances {
            if balance.denom.lowercased() == Chain.THORChain.ticker.lowercased() {
                guard let runeAmount = Double(balance.amount) else { return "Invalid balance" }
                let balanceRune = runeAmount / 100_000_000.0
                
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.maximumFractionDigits = 8
                formatter.minimumFractionDigits = 0
                formatter.groupingSeparator = ""
                formatter.decimalSeparator = "."
                return formatter.string(from: NSNumber(value: balanceRune))
            }
        }
        return "Balance not available"
    }
    
    var runeBalance: String? {
        guard let balances = balances else { return nil }
        for balance in balances {
            if balance.denom.lowercased() == Chain.THORChain.ticker.lowercased() {
                return balance.amount
            }
        }
        return nil
    }
    
    private init() {}
    
    func fetchBalances(_ address: String) async {
        if let cachedBalances = loadBalancesFromCache(forAddress: address) {
            self.balances = cachedBalances
            return
        }
        guard let url = URL(string: Endpoint.fetchAccountBalanceThorchainNineRealms(address: address)) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let balanceResponse = try JSONDecoder().decode(ThorchainBalanceResponse.self, from: data)
            self.balances = balanceResponse.balances
            self.cacheBalances(balanceResponse.balances, forAddress: address)
            
        } catch {
            self.errorMessage = Utils.handleJsonDecodingError(error)
        }
    }
    
    func fetchAccountNumber(_ address: String) async {
        guard let url = URL(string: Endpoint.fetchAccountNumberThorchainNineRealms(address)) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let accountResponse = try JSONDecoder().decode(ThorchainAccountNumberResponse.self, from: data)
            if let accountValue = accountResponse.result.value {
                self.account = accountValue
            }
            
        } catch {
            self.errorMessage = Utils.handleJsonDecodingError(error)
        }
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
              -cacheEntry.timestamp.timeIntervalSinceNow < 60
        else { // Checks if the cache is older than 1 minute
            return nil
        }
        
        return cacheEntry.balances
    }
}
