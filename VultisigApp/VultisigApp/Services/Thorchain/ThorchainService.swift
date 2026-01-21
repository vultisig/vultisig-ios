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

    private var cacheFeePrice = ThreadSafeDictionary<String, (data: ThorchainNetworkInfo, timestamp: Date)>()
    private var cacheInboundAddresses = ThreadSafeDictionary<String, (data: [InboundAddress], timestamp: Date)>()
    private var cacheAssetPrices = ThreadSafeDictionary<String, (data: Double, timestamp: Date)>()
    private var cacheLPPools = ThreadSafeDictionary<String, (data: [ThorchainPool], timestamp: Date)>()
    private var cacheLPPositions = ThreadSafeDictionary<String, (data: [ThorchainLPPosition], timestamp: Date)>()

    private init() {}

    func fetchBalances(_ address: String) async throws -> [CosmosBalance] {
        guard let url = URL(string: Endpoint.fetchAccountBalanceThorchainNineRealms(address: address)) else {
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
            for balance in balances where balance.denom.caseInsensitiveCompare("rune") != .orderedSame {
                var ticker: String
                var decimals: Int
                var logo: String

                do {
                    let metadata = try await getCosmosTokenMetadata(chain: .thorChain, denom: balance.denom)
                    ticker = metadata.ticker
                    decimals = metadata.decimals
                    logo = ticker.replacingOccurrences(of: "/", with: "")
                } catch {
                    let info = THORChainTokenMetadataFactory.create(asset: balance.denom)
                    ticker = info.ticker
                    decimals = info.decimals
                    logo = info.logo
                }

                // Find local asset to get correct logo and metadata
                let localAsset = TokensStore.TokenSelectionAssets.first(where: { $0.ticker.uppercased() == ticker.uppercased() })

                if ticker.range(of: "yrune", options: [.caseInsensitive, .anchored]) == nil &&
                    ticker.range(of: "ytcy", options: [.caseInsensitive, .anchored]) == nil &&
                    ticker.range(of: "stcy", options: [.caseInsensitive, .anchored]) == nil &&
                    ticker.range(of: "sruji", options: [.caseInsensitive, .anchored]) == nil {
                    ticker = ticker.uppercased()
                }

                // Use localAsset logo if available, otherwise use factory-generated logo
                let finalLogo = localAsset?.logo ?? logo

                let coinMeta = CoinMeta(
                    chain: .thorChain,
                    ticker: ticker,
                    logo: finalLogo,
                    decimals: decimals,
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

    func resolveTNS(name: String, chain: Chain) async throws -> String {
        struct Response: Codable {
            struct Entry: Codable {
                let address: String
                let chain: String
            }
            let entries: [Entry]
        }

        let url = Endpoint.resolveTNS(name: name, chain: chain)
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

    func get9RRequest(url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.addValue("vultisig", forHTTPHeaderField: "X-Client-ID")
        return req
    }

    func fetchSwapQuotes(
        address: String,
        fromAsset: String,
        toAsset: String,
        amount: String,
        interval: Int,
        referredCode: String,
        vultTierDiscount: Int
    ) async throws -> ThorchainSwapQuote {

        let url = Endpoint.fetchSwapQuoteThorchain(
            chain: .thorchain,
            address: address,
            fromAsset: fromAsset,
            toAsset: toAsset,
            amount: amount,
            interval: String(interval),
            referredCode: referredCode,
            vultTierDiscount: vultTierDiscount
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
        self.cacheFeePrice.set(cacheKey, (data: thorchainNetworkInfo, timestamp: Date()))
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
            self.cacheInboundAddresses.set(cacheKey, (data: inboundAddresses, timestamp: Date()))
            return inboundAddresses
        } catch {
            print("JSON decoding error: \(error.localizedDescription)")
            return []
        }
    }

    func getTHORChainChainID() async throws -> String {
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
                do {
                    _ = try await self.getTHORChainChainID()
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
        let poolResponse = try decoder.decode(THORChainPoolResponse.self, from: data)

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
                decoded.data.node?.stakingV2?.first else {
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
            return cached.data
        }

        // Get all available pools first (this will use cache if available)
        let pools = try await fetchLPPools()
        var allPositions: [ThorchainLPPosition] = []

        // Check each pool for LP positions
        // Use sequential requests with small delay to avoid rate limiting
        for pool in pools {
            do {
                let poolUrlString = Endpoint.fetchThorchainPoolLiquidityProvider(asset: pool.asset, address: address)
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

        return allPositions
    }

    /// Fetch pool information for a specific asset
    func fetchPoolInfo(asset: String) async throws -> ThorchainPool {
        let urlString = Endpoint.fetchPoolInfo(asset: asset)

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
            return cached.data
        }

        // Use retry mechanism for network call
        return try await withRetry(maxAttempts: 3) {
            let urlString = Endpoint.fetchThorchainPools

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
                }
            }
        }

        throw lastError ?? HelperError.runtimeError("Unknown error after \(maxAttempts) attempts")
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
            pool {
              summary {
                apr {
                  value
                }
              }
            }
          }
        }
      }
    }
    """

    // MARK: - Models
    enum Errors: Error {
        case tnsEntryNotFound
        case invalidURL
        case invalidPriceFormat
        case invalidResponse
        case apiError(String)
    }

}

struct THORChainPoolResponse: Codable {
    let status: String
    let asset: String
    let decimals: Int?
    let balanceAsset: String
    let balanceRune: String
    let assetTorPrice: String

    enum CodingKeys: String, CodingKey {
        case status
        case asset
        case decimals
        case balanceAsset = "balance_asset"
        case balanceRune = "balance_rune"
        case assetTorPrice = "asset_tor_price"
    }
}

struct DenomUnit: Decodable {
    let denom: String
    let exponent: Int
}

struct DenomMetadata: Decodable {
    let base: String?
    let symbol: String?
    let display: String?
    let denom_units: [DenomUnit]?

    enum CodingKeys: String, CodingKey {
        case base, symbol, display
        case denom_units
    }
}

struct MetadataResponse: Decodable {
    let metadata: DenomMetadata?
}

struct MetadatasResponse: Decodable {
    let metadatas: [DenomMetadata]?
}

struct CosmosTokenMetadata {
    let ticker: String
    let decimals: Int
}

extension ThorchainService {

    private func getCosmosTokenMetadata(chain: Chain, denom: String) async throws -> CosmosTokenMetadata {
        guard let metadata = try await getDenomMetaFromLCD(denom: denom) else {
            throw CosmosTokenMetadataError.noDenomMetaAvailable
        }

        guard let decimals = decimalsFromMeta(metadata: metadata) else {
            throw CosmosTokenMetadataError.couldNotFetchDecimals
        }

        let ticker = deriveTicker(denom: denom, metadata: metadata)

        return CosmosTokenMetadata(ticker: ticker, decimals: decimals)
    }

    private func getDenomMetaFromLCD(denom: String) async throws -> DenomMetadata? {
        if let metadata = try await attemptDirectFetch(denom: denom) {
            return metadata
        }

        if let metadata = try await attemptListFetch(denom: denom) {
            return metadata
        }

        return nil
    }

    private func decimalsFromMeta(metadata: DenomMetadata) -> Int? {
        guard let denomUnits = metadata.denom_units,
              let display = metadata.display else {
            return nil
        }

        for unit in denomUnits {
            if unit.denom == display && unit.exponent > 0 {
                return unit.exponent
            }
        }

        if let symbol = metadata.symbol {
            for unit in denomUnits {
                if unit.denom == symbol {
                    return unit.exponent
                }
            }
        }

        return nil
    }

    private func deriveTicker(denom: String, metadata: DenomMetadata) -> String {
        if let symbol = metadata.symbol, !symbol.isEmpty {
            return symbol
        }

        if let display = metadata.display, !display.isEmpty {
            return display
        }

        if denom.hasPrefix("x/staking-") {
            let withoutPrefix = String(denom.dropFirst("x/staking-".count))
            return "S" + withoutPrefix.uppercased()
        }

        if denom.hasPrefix("x/") {
            let components = denom.components(separatedBy: "/")
            if let lastComponent = components.last {
                return lastComponent
            }
        }

        if denom.hasPrefix("factory/") {
            let components = denom.components(separatedBy: "/")
            if let lastComponent = components.last {
                if lastComponent.hasPrefix("u") && lastComponent.count > 1 {
                    return String(lastComponent.dropFirst())
                }
                return lastComponent
            }
        }

        return denom
    }

    private func attemptDirectFetch(denom: String) async throws -> DenomMetadata? {
        let urlString = Endpoint.fetchThorchainDenomMetadata(denom: denom)

        guard let url = URL(string: urlString) else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                let metadataResponse = try JSONDecoder().decode(MetadataResponse.self, from: data)
                return metadataResponse.metadata
            }
        } catch {
            return nil
        }

        return nil
    }

    private func attemptListFetch(denom: String) async throws -> DenomMetadata? {
        let urlString = Endpoint.fetchThorchainAllDenomMetadata()

        guard let url = URL(string: urlString) else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                let metadatasResponse = try JSONDecoder().decode(MetadatasResponse.self, from: data)

                if let metadatas = metadatasResponse.metadatas {
                    for metadata in metadatas {
                        if metadata.base == denom {
                            return metadata
                        }
                    }
                }
            }
        } catch {
            return nil
        }

        return nil
    }
}

enum CosmosTokenMetadataError: Error, LocalizedError {
    case noDenomMetaAvailable
    case couldNotFetchDecimals

    var errorDescription: String? {
        switch self {
        case .noDenomMetaAvailable:
            return "No denom meta information available"
        case .couldNotFetchDecimals:
            return "Could not fetch decimal for token"
        }
    }
}
