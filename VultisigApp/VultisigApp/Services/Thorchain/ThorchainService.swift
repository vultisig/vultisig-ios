//
//  ThorchainService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 06/03/2024.
//

import Foundation

class ThorchainService {
    static let shared = ThorchainService()
    
    private var cacheFeePrice: [String: (data: UInt64, timestamp: Date)] = [:]
    
    private init() {}
    
    func fetchBalances(_ address: String) async throws -> [CosmosBalance] {
        let cachedBalances = loadBalancesFromCache(forAddress: address)
        if cachedBalances.count > 0 {
            return cachedBalances
        }
        guard let url = URL(string: Endpoint.fetchAccountBalanceThorchainNineRealms(address: address)) else        {
            return [CosmosBalance]()
        }
        let (data, _) = try await URLSession.shared.data(for: get9RRequest(url: url))
        
        let balanceResponse = try JSONDecoder().decode(CosmosBalanceResponse.self, from: data)
        self.cacheBalances(balanceResponse.balances, forAddress: address)
        return balanceResponse.balances
    }
    
    func fetchAccountNumber(_ address: String) async throws -> THORChainAccountValue? {
        guard let url = URL(string: Endpoint.fetchAccountNumberThorchainNineRealms(address)) else {
            return nil
        }
        let (data, _) = try await URLSession.shared.data(for: get9RRequest(url: url))
        let accountResponse = try JSONDecoder().decode(THORChainAccountNumberResponse.self, from: data)
        return accountResponse.result.value
    }
    
    func get9RRequest(url: URL) -> URLRequest{
        var req = URLRequest(url:url)
        req.addValue("vultisig", forHTTPHeaderField: "X-Client-ID")
        return req
    }
    
    func fetchSwapQuotes(address: String, fromAsset: String, toAsset: String, amount: String, interval: String, isAffiliate: Bool) async throws -> ThorchainSwapQuote {
        let url = Endpoint.fetchSwapQuoteThorchain(chain: .thorchain, address: address, fromAsset: fromAsset, toAsset: toAsset, amount: amount, interval: interval, isAffiliate: isAffiliate)
        let (data, _) = try await URLSession.shared.data(for: get9RRequest(url: url))
        do {
            let response = try JSONDecoder().decode(ThorchainSwapQuote.self, from: data)
            return response
        } catch {
            let error = try JSONDecoder().decode(ThorchainSwapError.self, from: data)
            throw error
        }
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
    
    func fetchFeePrice() async throws -> UInt64 {
        let cacheKey = "thorchain-fee-price"
        if let cachedData: UInt64 = await Utils.getCachedData(cacheKey: cacheKey, cache: cacheFeePrice, timeInSeconds: 60*5) {
            return cachedData
        }
        
        let urlString = Endpoint.fetchThorchainNetworkInfoNineRealms
        let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        
        if let result = Utils.extractResultFromJson(fromData: data, path: "native_tx_fee_rune") as? String,
           let resultNumber = UInt64(result) {
            self.cacheFeePrice[cacheKey] = (data: resultNumber, timestamp: Date())
            return resultNumber
        } else {
            print("JSON decoding error")
        }
        
        return .zero
    }
    
    private var cachedTHORChainGas: UInt64?
    private func fetchTHORChainGas(completion: @escaping (UInt64) -> Void) {
        if let gas = cachedTHORChainGas {
            completion(gas)
        } else {
            Task {
                do {
                    let feePrice = try await self.fetchFeePrice()
                    cachedTHORChainGas = feePrice
                    completion(feePrice)
                } catch {
                    print("Failed to fetch THORChain gas price: \(error)")
                    completion(0) // or any default value you see fit
                }
            }
        }
    }
    
    func getTHORChainGasPrice() -> UInt64 {
        let semaphore = DispatchSemaphore(value: 0)
        var gasPrice: UInt64 = 0
        
        fetchTHORChainGas { price in
            gasPrice = price
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .distantFuture)
        return gasPrice
    }
}
