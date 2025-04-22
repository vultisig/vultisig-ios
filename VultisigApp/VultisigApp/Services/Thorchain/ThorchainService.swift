//
//  ThorchainService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 06/03/2024.
//

import Foundation

class ThorchainService: ThorchainSwapProvider {
    var network: String = ""
    static let shared = ThorchainService()
    
    private var cacheFeePrice: [String: (data: ThorchainNetworkInfo, timestamp: Date)] = [:]
    private var cacheInboundAddresses: [String: (data: [InboundAddress], timestamp: Date)] = [:]
    
    private init() {}
    
    func fetchBalances(_ address: String) async throws -> [CosmosBalance] {
        guard let url = URL(string: Endpoint.fetchAccountBalanceThorchainNineRealms(address: address)) else        {
            return [CosmosBalance]()
        }
        let (data, _) = try await URLSession.shared.data(for: get9RRequest(url: url))
        let balanceResponse = try JSONDecoder().decode(CosmosBalanceResponse.self, from: data)
        return balanceResponse.balances
    }
    
    func fetchTokens(_ address: String) async throws -> [CoinMeta] {
        do {
            let balances: [CosmosBalance] =  try await fetchBalances(address)
            var coinMetaList = [CoinMeta]()
            for balance in balances {
                let info = getTokenMetadata(for: balance.denom)
                let coinMeta = CoinMeta(
                    chain: .thorChain,
                    ticker: info.symbol,
                    logo: info.logo, // We will have to move this logo to another storage
                    decimals: 8,
                    priceProviderId: "", // we don't know the provider ID
                    contractAddress: balance.denom,
                    isNativeToken: false
                )
                coinMetaList.append(coinMeta)
            }
            return coinMetaList
        } catch {
            print("Error in fetchTokens: \(error)")
            throw error
        }
    }
    
    func getTokenMetadata(for denom: String) -> TokenMetadata {
        let decimals = 8
        var chain = ""
        var symbol = ""
        var ticker = ""
        var logo = ""
        
        if denom.contains(".") {
            // Switch asset: thor.fuzn
            let parts = denom.split(separator: ".")
            if parts.count >= 2 {
                chain = parts[0].uppercased()
                symbol = parts[1].uppercased()
                ticker = parts[1].lowercased()
            }
        } else if denom.contains("-") {
            let parts = denom.split(separator: "-")
            if parts.count >= 2 {
                chain = parts[0].uppercased()
                symbol = parts[1].uppercased()
                ticker = parts[1].lowercased()
            }
        } else {
            // Native THORChain asset (e.g., rune)
            chain = "THOR"
            symbol = denom.uppercased()
            ticker = denom.lowercased()
        }
        
        logo = ticker // It will use whatever is in our asset list
        
        return TokenMetadata(chain: chain, ticker: ticker, symbol: symbol, decimals: decimals, logo: logo)
    }
    
    func resolveTNS(name: String, chain: Chain) async throws -> String {
        struct Response: Codable {
            struct Entry: Codable {
                let address: String
                let chain: String
            }
            let entries: [Entry]
        }
        
        let url = Endpoint.resolveTNS(name: name)
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(Response.self, from: data)
        
        guard let entry = response.entries.first(where: {
            $0.chain.lowercased() == chain.swapAsset.lowercased()
        }) else {
            throw Errors.tnsEntryNotFound
        }
        
        return entry.address
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
    
    func fetchSwapQuotes(address: String,
                         fromAsset: String,
                         toAsset: String,
                         amount: String,
                         interval: Int,
                         isAffiliate: Bool) async throws -> ThorchainSwapQuote {
        
        let url = Endpoint.fetchSwapQuoteThorchain(
            chain: .thorchain,
            address: address,
            fromAsset: fromAsset,
            toAsset: toAsset,
            amount: amount,
            interval: String(interval),
            isAffiliate: isAffiliate
        )
        
        let (data, _) = try await URLSession.shared.data(for: get9RRequest(url: url))
        
        do {
            let response = try JSONDecoder().decode(ThorchainSwapQuote.self, from: data)
            return response
        } catch {
            let error = try JSONDecoder().decode(ThorchainSwapError.self, from: data)
            throw error
        }
    }
    
    func fetchFeePrice() async throws -> UInt64 {
        let cacheKey = "thorchain-fee-price"
        if let cachedData = await Utils.getCachedData(cacheKey: cacheKey, cache: cacheFeePrice, timeInSeconds: 60*5) {
            return UInt64(cachedData.native_tx_fee_rune) ?? 0
        }
        
        let urlString = Endpoint.fetchThorchainNetworkInfoNineRealms
        let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        let thorchainNetworkInfo = try JSONDecoder().decode(ThorchainNetworkInfo.self, from: data)
        self.cacheFeePrice[cacheKey] = (data: thorchainNetworkInfo, timestamp: Date())
        return UInt64(thorchainNetworkInfo.native_tx_fee_rune) ?? 0
    }
    
    func fetchThorchainInboundAddress() async -> [InboundAddress] {
        do {
            let cacheKey = "thorchain-inbound-address"
            
            if let cachedData = await Utils.getCachedData(
                cacheKey: cacheKey,
                cache: cacheInboundAddresses,
                timeInSeconds: 60 * 5
            ) {
                return cachedData
            }
            
            let urlString = Endpoint.fetchThorchainInboundAddressesNineRealms
            let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
            let inboundAddresses = try JSONDecoder().decode([InboundAddress].self, from: data)
            self.cacheInboundAddresses[cacheKey] = (data: inboundAddresses, timestamp: Date())
            return inboundAddresses
        } catch {
            print("JSON decoding error: \(error.localizedDescription)")
            return []
        }
    }
    
    func getTHORChainChainID() async throws -> String  {
        if !network.isEmpty {
            print("network id\(network)")
            return network
        }
        let (data, _) = try await URLSession.shared.data(from: Endpoint.thorchainNetworkInfo)
        let response = try JSONDecoder().decode(THORChainNetworkStatus.self, from: data)
        network = response.result.node_info.network
        return response.result.node_info.network
    }
    
    func ensureTHORChainChainID() -> String {
        if !network.isEmpty {
            return network
        }
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            Task {
                do{
                    _ =  try await self.getTHORChainChainID()
                } catch {
                    print("fail to get thorchain id \(error.localizedDescription)")
                }
                group.leave()
            }
        }
        group.wait()
        return network
    }
}


private extension ThorchainService {
    
    enum Errors: Error {
        case tnsEntryNotFound
    }
}
