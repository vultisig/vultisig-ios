//
//  ThorchainService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 06/03/2024.
//

import Foundation
import BigInt

class ThorchainService: ThorchainSwapProvider {
    var network: String = ""
    static let shared = ThorchainService()
    
    private var cacheFeePrice = ThreadSafeDictionary<String,(data: ThorchainNetworkInfo, timestamp: Date)>()
    private var cacheInboundAddresses = ThreadSafeDictionary<String,(data: [InboundAddress], timestamp: Date)>()
    private var cacheAssetPrices = ThreadSafeDictionary<String,(data: Double, timestamp: Date)>()
    private var cacheLPPools = ThreadSafeDictionary<String,(data: [ThorchainPool], timestamp: Date)>()
    private var cacheLPPositions = ThreadSafeDictionary<String,(data: [ThorchainLPPosition], timestamp: Date)>()
    
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
                
                // We don't care about the chain in that case, since we only want the Price Provider ID and it is the same in all networks.
                let localAsset = TokensStore.TokenSelectionAssets.first(where: { $0.ticker.uppercased() == info.symbol.uppercased() })
                
                let coinMeta = CoinMeta(
                    chain: .thorChain,
                    ticker: info.symbol.uppercased().replacingOccurrences(of: "X/", with: ""),
                    logo: info.logo, // We will have to move this logo to another storage
                    decimals: 8,
                    priceProviderId: localAsset?.priceProviderId ?? "",
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
        
        logo = ticker.replacingOccurrences(of: "/", with: "") // It will use whatever is in our asset list
        
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
    
    func fetchSwapQuotes(
        address: String,
        fromAsset: String,
        toAsset: String,
        amount: String,
        interval: Int,
        isAffiliate: Bool,
        referredCode: String
    ) async throws -> ThorchainSwapQuote {
        
        let url = Endpoint.fetchSwapQuoteThorchain(
            chain: .thorchain,
            address: address,
            fromAsset: fromAsset,
            toAsset: toAsset,
            amount: amount,
            interval: String(interval),
            isAffiliate: isAffiliate,
            referredCode: referredCode
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
        self.cacheFeePrice.set(cacheKey,(data: thorchainNetworkInfo, timestamp: Date()))
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
            self.cacheInboundAddresses.set(cacheKey,(data: inboundAddresses, timestamp: Date()))
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
    
    /// Clean pool name by removing contract addresses
    /// Example: "ETH.USDC-0x1234..." -> "ETH.USDC"
    static func cleanPoolName(_ asset: String) -> String {
        if let dashIndex = asset.firstIndex(of: "-") {
            let suffix = asset[asset.index(after: dashIndex)...]
            if suffix.uppercased().starts(with: "0X") {
                return String(asset[..<dashIndex])
            }
        }
        return asset
    }
    
    /// Get THORChain inbound chain name for a given chain
    static func getInboundChainName(for chain: Chain) -> String {
        switch chain {
        case .bitcoin:
            return "BTC"
        case .ethereum:
            return "ETH"
        case .avalanche:
            return "AVAX"
        case .bscChain:
            return "BSC"
        case .arbitrum:
            return "ARB"
        case .base:
            return "BASE"
        case .optimism:
            return "OP"
        case .litecoin:
            return "LTC"
        case .bitcoinCash:
            return "BCH"
        case .dogecoin:
            return "DOGE"
        case .gaiaChain:
            return "GAIA"
        case .thorChain:
            return "THOR"
        default:
            return chain.swapAsset.uppercased()
        }
    }
}

// MARK: - THORChain Pool Prices Functionality
extension ThorchainService {
    
    /// Get price in USD for any THORChain asset using the pools endpoint
    /// - Parameter assetName: The fully qualified asset name (e.g., "THOR.TCY", "BTC.BTC", etc.)
    /// - Returns: The current asset price in USD, or 0.0 if not available
    func getAssetPriceInUSD(assetName: String) async -> Double {
        let cacheKey = "\(assetName.lowercased())-price"
        
        // Check cache first
        if let cachedData = await Utils.getCachedData(cacheKey: cacheKey, cache: cacheAssetPrices, timeInSeconds: 60*5) {
            return cachedData
        }
        
        // Fetch fresh data if cache expired or doesn't exist
        do {
            let price = try await fetchAssetPrice(assetName: assetName)
            if price > 0 {
                self.cacheAssetPrices.set(cacheKey, (data: price, timestamp: Date()))
            }
            return price
        } catch {
            print("Error in getAssetPriceInUSD: \(error.localizedDescription)")
            return 0.0
        }
    }
    
    /// Check if an asset exists in THORChain pools
    /// - Parameter assetName: The fully qualified asset name to check
    /// - Returns: True if the asset exists in THORChain pools
    func assetExistsInPools(assetName: String) async -> Bool {
        do {
            _ = try await fetchAssetPrice(assetName: assetName)
            return true
        } catch {
            print("Error in assetExistsInPools: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Get THORChain asset name in the format expected by the API
    /// - Parameters:
    ///   - chain: The chain the asset is on
    ///   - symbol: The ticker/symbol of the asset
    /// - Returns: Formatted asset name (e.g., "THOR.RUNE", "BTC.BTC")
    func formatAssetName(chain: Chain, symbol: String) -> String {
        // For THORChain assets, the chain code should be "THOR"
        let chainCode = chain == .thorChain ? "THOR" : chain.rawValue.uppercased()
        
        // Uppercase the symbol
        let assetSymbol = symbol.uppercased()
        
        return "\(chainCode).\(assetSymbol)"
    }
    
    private func fetchAssetPrice(assetName: String) async throws -> Double {
        // Use the generic pool endpoint for all assets
        let endpoint = Endpoint.fetchPoolInfo(asset: assetName)
        
        guard let url = URL(string: endpoint) else {
            throw Errors.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Errors.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            throw Errors.apiError("HTTP Error: \(httpResponse.statusCode)")
        }
        
        let decoder = JSONDecoder()
        let poolResponse = try decoder.decode(PoolResponse.self, from: data)
        
        // Convert from 8 decimal places to a decimal value
        guard let priceValue = Double(poolResponse.assetTorPrice) else {
            throw Errors.invalidPriceFormat
        }
        
        // Convert from 8 decimal places (e.g., 22840997 = $0.22840997)
        let price = priceValue / 100_000_000
        return price
    }
}

// MARK: - RUJI Merge/Unmerge Functionality
extension ThorchainService {
    
    /// Structure representing a RUJI balance result
    struct RujiBalance {
        let ruji: Decimal
        let shares: String
        let price: Decimal
    }
    
    /// Structure representing a merged RUJI position
    struct MergedPosition {
        let token: String
        let ruji: Decimal
        let shares: String
    }
    
    /// Structure representing a RUJI Stake balance result
    struct RujiStakeBalance {
        let stakeAmount: BigInt
        let stakeTicker: String
        let rewardsAmount: BigInt
        let rewardsTicker: String
        
        static let empty = RujiStakeBalance(stakeAmount: .zero, stakeTicker: "", rewardsAmount: .zero, rewardsTicker: "")
    }
    
    /// Fetch merged RUJI balance for a specific token
    /// - Parameters:
    ///   - thorAddress: The THORChain address to query
    ///   - tokenSymbol: The token symbol to check (e.g., "THOR.KUJI", "THOR.RKUJI")
    /// - Returns: A tuple containing (ruji amount, shares, price per share)
    func fetchRujiMergeBalance(thorAddr: String, tokenSymbol: String) async throws -> RujiBalance {
        let id = "Account:\(thorAddr)".data(using: .utf8)?.base64EncodedString() ?? ""
        
        guard let url = URL(string: Endpoint.fetchThorchainMergedAssets()) else {
            throw HelperError.runtimeError("Invalid GraphQL URL")
        }
        
        let query = String(format: Self.mergedAssetsQuery, id)
        
        let requestBody: [String: Any] = ["query": query]
        
        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        let decoded = try JSONDecoder().decode(AccountRootData.self, from: data)
        
        // Find the account matching the selected token
        let cleanTokenSymbol = tokenSymbol.lowercased().replacingOccurrences(of: "thor.", with: "")
        
        let acc = decoded.data.node?.merge?.accounts.first { account in
            account.pool.mergeAsset.metadata.symbol.lowercased() == cleanTokenSymbol
        }
        
        guard let acc = acc else {
            return RujiBalance(ruji: 0, shares: "0", price: 0)
        }
        
        let shares = acc.shares
        let ruji = Decimal(string: acc.size.amount) ?? 0
        // Calculate price per share based on user's own position
        let sharesDecimal = Decimal(string: shares) ?? 1
        let price = sharesDecimal > 0 ? ruji / sharesDecimal : 0
        
        return RujiBalance(ruji: ruji, shares: shares, price: price)
    }
    
    
    /// Fetch all merged RUJI positions for an address
    /// - Parameter thorAddress: The THORChain address to query
    /// - Returns: Array of merged positions with token info
    func fetchAllMergedPositions(thorAddr: String) async throws -> [MergedPosition] {
        let id = "Account:\(thorAddr)".data(using: .utf8)?.base64EncodedString() ?? ""
        
        guard let url = URL(string: Endpoint.fetchThorchainMergedAssets()) else {
            throw HelperError.runtimeError("Invalid GraphQL URL")
        }
        
        let query = String(format: Self.mergedAssetsQuery, id)
        
        let requestBody: [String: Any] = ["query": query]
        
        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        let decoded = try JSONDecoder().decode(AccountRootData.self, from: data)
        
        var positions: [MergedPosition] = []
        
        if let accounts = decoded.data.node?.merge?.accounts {
            for account in accounts {
                let token = account.pool.mergeAsset.metadata.symbol
                let ruji = Decimal(string: account.size.amount) ?? 0
                let shares = account.shares
                positions.append(MergedPosition(token: token, ruji: ruji, shares: shares))
            }
        }
        
        return positions
    }
    
    func fetchRujiStakeBalance(thorAddr: String, tokenSymbol: String) async throws -> RujiStakeBalance {
        let id = "Account:\(thorAddr)".data(using: .utf8)?.base64EncodedString() ?? ""
        
        guard let url = URL(string: Endpoint.fetchThorchainMergedAssets()) else {
            throw HelperError.runtimeError("Invalid GraphQL URL")
        }
        
        let query = String(format: Self.stakeQuery, id)
        
        let requestBody: [String: Any] = ["query": query]
        
        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        let decoded = try JSONDecoder().decode(AccountRootData.self, from: data)
        
        guard let stake =
                decoded.data.node?.stakingV2.first else {
            return .empty
        }
        
        let stakeAmount = BigInt(stake.bonded.amount) ?? .zero
        let stakeTicker = stake.bonded.asset.metadata?.symbol ?? ""
        let rewardsAmount = BigInt(stake.pendingRevenue?.amount ?? .empty) ?? .zero
        let rewardsTicker = stake.pendingRevenue?.asset.metadata?.symbol ?? .empty
        
        return RujiStakeBalance(
            stakeAmount: stakeAmount,
            stakeTicker: stakeTicker,
            rewardsAmount: rewardsAmount,
            rewardsTicker: rewardsTicker
        )
    }
}

// MARK: - THORChain LP Functionality
extension ThorchainService {
    
    /// Fetch LP positions for a given address with caching
    func fetchLPPositions(runeAddress: String? = nil, assetAddress: String? = nil) async throws -> [ThorchainLPPosition] {
        let targetAddress = runeAddress ?? assetAddress
        guard let address = targetAddress else {
            throw HelperError.runtimeError("Either rune address or asset address must be provided")
        }
        
        let cacheKey = "lp_positions_\(address)"
        let cacheExpirationMinutes = 2.0 // Cache for 2 minutes
        
        // Check cache first
        if let cached = cacheLPPositions.get(cacheKey),
           Date().timeIntervalSince(cached.timestamp) < cacheExpirationMinutes * 60 {
            print("ThorchainService: Using cached LP positions for \(address) (count: \(cached.data.count))")
            return cached.data
        }
        
        print("ThorchainService: Fetching LP positions for address: \(address)")
        
        // Get all available pools first (this will use cache if available)
        let pools = try await fetchLPPools()
        var allPositions: [ThorchainLPPosition] = []
        
        // Check each pool for LP positions
        // Use sequential requests with small delay to avoid rate limiting
        for pool in pools {
            do {
                let poolUrlString = "https://thornode.ninerealms.com/thorchain/pool/\(pool.asset)/liquidity_provider/\(address)"
                guard let poolUrl = URL(string: poolUrlString) else { continue }
                
                let (poolData, response) = try await URLSession.shared.data(for: get9RRequest(url: poolUrl))
                
                // Check if we got a 404 (no position in this pool)
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 404 {
                    continue
                }
                
                // Try to decode as pool LP response
                if let lpResponse = try? JSONDecoder().decode(ThorchainPoolLPResponse.self, from: poolData) {
                    // Only add if units > 0
                    if let units = Int64(lpResponse.units), units > 0 {
                        let position = ThorchainLPPosition(
                            asset: lpResponse.asset,
                            runeAddress: runeAddress,
                            assetAddress: lpResponse.assetAddress,
                            poolUnits: lpResponse.units,
                            runeDepositValue: lpResponse.runeDepositValue,
                            assetDepositValue: lpResponse.assetDepositValue,
                            runeRedeemValue: nil,
                            assetRedeemValue: nil,
                            luvi: nil,
                            gLPGrowth: nil,
                            assetGrowthPct: nil
                        )
                        allPositions.append(position)
                        print("ThorchainService: Found LP position in \(pool.asset) with \(lpResponse.units) units")
                    }
                }
                
                // Add small delay to avoid rate limiting
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                
            } catch {
                // Skip pools where user has no position
                continue
            }
        }
        
        // Cache the result
        cacheLPPositions.set(cacheKey, (data: allPositions, timestamp: Date()))
        print("ThorchainService: Cached \(allPositions.count) LP positions for \(address)")
        
        return allPositions
        
        // For RUNE addresses, we also need to check by searching for the Thor address in pool LPs
        if runeAddress != nil {
            // The RUNE LP would be matched via the asset address field when adding symmetric LP
            // But for pure RUNE LP, we need a different approach
            // For now, we'll rely on the asset-side matching above
        }
        
        return allPositions
    }
    
    /// Fetch pool information for a specific asset
    func fetchPoolInfo(asset: String) async throws -> ThorchainPool {
        let urlString = "https://thornode.ninerealms.com/thorchain/pool/\(asset)"
        
        guard let url = URL(string: urlString) else {
            throw HelperError.runtimeError("Invalid URL")
        }
        
        let (data, _) = try await URLSession.shared.data(for: get9RRequest(url: url))
        let pool = try JSONDecoder().decode(ThorchainPool.self, from: data)
        return pool
    }
    
    /// Get supported pools for LP with caching
    func fetchLPPools() async throws -> [ThorchainPool] {
        let cacheKey = "lp_pools"
        let cacheExpirationMinutes = 5.0 // Cache for 5 minutes
        
        // Check cache first
        if let cached = cacheLPPools.get(cacheKey),
           Date().timeIntervalSince(cached.timestamp) < cacheExpirationMinutes * 60 {
            print("ThorchainService: Using cached LP pools (count: \(cached.data.count))")
            return cached.data
        }
        
        // Use retry mechanism for network call
        return try await withRetry(maxAttempts: 3) {
            let urlString = "https://thornode.ninerealms.com/thorchain/pools"
            
            guard let url = URL(string: urlString) else {
                throw HelperError.runtimeError("Invalid URL")
            }
            
            // Create a URL session with timeout
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 10.0 // 10 second timeout
            config.timeoutIntervalForResource = 15.0
            let session = URLSession(configuration: config)
            
            let (data, _) = try await session.data(for: get9RRequest(url: url))
            let pools = try JSONDecoder().decode([ThorchainPool].self, from: data)
            
            // Filter only available pools
            let availablePools = pools.filter { $0.status == "Available" }
            
            // Cache the result
            cacheLPPools.set(cacheKey, (data: availablePools, timestamp: Date()))
            print("ThorchainService: Cached \(availablePools.count) LP pools")
            
            return availablePools
        }
    }
    
    /// Generic retry mechanism for async operations
    private func withRetry<T>(maxAttempts: Int = 3, retryDelay: TimeInterval = 1.0, operation: () async throws -> T) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    // Exponential backoff: 1s, 2s, 4s
                    let delay = retryDelay * pow(2.0, Double(attempt - 1))
                    try await Task.sleep(for: .seconds(delay))
                    print("ThorchainService: Retry attempt \(attempt) after \(delay)s delay")
                }
            }
        }
        
        throw lastError ?? HelperError.runtimeError("Unknown error after \(maxAttempts) attempts")
    }
    
    /// Clear LP pools cache
    func clearLPPoolsCache() async {
        await cacheLPPools.clear()
        print("ThorchainService: Cleared LP pools cache")
    }
    
    /// Clear all LP-related caches
    func clearAllLPCaches() async {
        await cacheLPPools.clear()
        await cacheLPPositions.clear()
        print("ThorchainService: Cleared all LP caches")
    }
    
    /// Calculate asset amount needed for symmetric LP
    func calculateSymmetricLPAssetAmount(runeAmount: Decimal, pool: ThorchainPool) -> Decimal? {
        guard let balanceRune = Decimal(string: pool.balanceRune),
              let balanceAsset = Decimal(string: pool.balanceAsset),
              balanceRune > 0 else {
            return nil
        }
        
        // For symmetric LP: assetAmount = runeAmount * (balanceAsset / balanceRune)
        return runeAmount * (balanceAsset / balanceRune)
    }
}

private extension ThorchainService {
    // MARK: - GraphQL Queries
    static let mergedAssetsQuery = """
    {
      node(id: "%@") {
        ... on Account {
          merge {
            accounts {
              shares
              size { amount }
              pool { 
                mergeAsset {
                  metadata {
                    symbol
                  }
                }
              }
            }
          }
        }
      }
    }
    """
    
    static let stakeQuery = """
    {
      node(id:"%@") {
        ... on Account {
          stakingV2 {
            account
            bonded {
              amount
              asset {
                metadata {
                  symbol
                }
              }
            }
            pendingRevenue {
              amount
              asset {
                metadata {
                  symbol
                }
              }
            }
          }
        }
      }
    }
    """
    
    // MARK: - Models
    /// Response model for pool data from the THORChain API
    struct PoolResponse: Codable {
        let status: String
        let asset: String
        let decimals: Int
        let balanceAsset: String
        let balanceRune: String
        
        // The TCY price in TOR (8 decimal places)
        let assetTorPrice: String
        
        enum CodingKeys: String, CodingKey {
            case status
            case asset
            case decimals
            case balanceAsset = "balance_asset"
            case balanceRune = "balance_rune"
            case assetTorPrice = "asset_tor_price"  // This is the actual price field in the API
        }
    }
    
    enum Errors: Error {
        case tnsEntryNotFound
        case invalidURL
        case invalidPriceFormat
        case invalidResponse
        case apiError(String)
    }
    
}

