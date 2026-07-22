//
//  ThorchainService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 06/03/2024.
//

import Foundation
import BigInt
import OSLog

class ThorchainService: ThorchainSwapProvider {
    var network: String = ""
    static let shared = ThorchainService()
    let logger = Logger(subsystem: "com.vultisig.app", category: "thorchain-service")

    /// Injectable so the sign-time halt gate is unit-testable with a stubbed
    /// inbound response (same pattern as `MayachainService`); production uses
    /// the default `HTTPClient`.
    let httpClient: HTTPClientProtocol

    /// Resolves the THORChain custom RPC override. Injected so the API values
    /// are built from a dependency rather than a global reach-in; resolution
    /// happens per request inside `mainnet(_:)` so a runtime override change is
    /// picked up live (the shared mirror updates without a relaunch).
    private let resolver: RPCEndpointResolving

    private var cacheFeePrice = ThreadSafeDictionary<String, (data: ThorchainNetworkInfo, timestamp: Date)>()
    private var cacheInboundAddresses = ThreadSafeDictionary<String, (data: [InboundAddress], timestamp: Date)>()
    private var cacheAssetPrices = ThreadSafeDictionary<String, (data: Double, timestamp: Date)>()
    private var cacheLPPools = ThreadSafeDictionary<String, (data: [ThorchainPool], timestamp: Date)>()
    private var cacheSecuredAssets = ThreadSafeDictionary<String, (data: [ThorchainSecuredAsset], timestamp: Date)>()
    private var cacheLPPositions = ThreadSafeDictionary<String, (data: [ThorchainLPPosition], timestamp: Date)>()

    init(
        resolver: RPCEndpointResolving = CustomRPCStore.shared,
        httpClient: HTTPClientProtocol = HTTPClient()
    ) {
        self.resolver = resolver
        self.httpClient = httpClient
    }

    /// The override-aware THORChain LCD host. Falls back to the default host
    /// when no override is set. Exposed so the broadcast path can reuse it. The
    /// single `.thorChain` override intentionally replaces both the LCD and RPC
    /// hosts (see `resolvedRPCHost`).
    var resolvedLCDHost: URL {
        resolver.resolvedURL(for: .thorChain, default: ThorchainMainnetAPI.defaultLCDHost)
    }

    private var resolvedRPCHost: URL {
        resolver.resolvedURL(for: .thorChain, default: ThorchainMainnetAPI.defaultRPCHost)
    }

    /// Builds a pure `ThorchainMainnetAPI` value with the resolved LCD / RPC
    /// hosts baked in. The `TargetType` itself never consults the resolver.
    func mainnet(_ endpoint: ThorchainMainnetAPI.Endpoint) -> ThorchainMainnetAPI {
        ThorchainMainnetAPI(endpoint, lcdHost: resolvedLCDHost, rpcHost: resolvedRPCHost)
    }

    func fetchBalances(_ address: String) async throws -> [CosmosBalance] {
        let response = try await httpClient.request(
            mainnet(.balances(address: address)),
            responseType: CosmosBalanceResponse.self
        )
        return response.data.balances
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
                    let metadata = try await getCosmosTokenMetadata(denom: balance.denom)
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
                    ticker.range(of: "sruji", options: [.caseInsensitive, .anchored]) == nil &&
                    ticker.range(of: "ybrune", options: [.caseInsensitive, .anchored]) == nil &&
                    ticker.range(of: "brune", options: [.caseInsensitive, .anchored]) == nil {
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
            logger.debug("Error in fetchTokens: \(error)")
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

        let response = try await httpClient.request(
            mainnet(.resolveTNS(name: name, chain: chain)),
            responseType: Response.self
        )

        guard let entry = response.data.entries.first(where: {
            $0.chain.lowercased() == chain.swapAsset.lowercased()
        }) else {
            throw Errors.tnsEntryNotFound
        }

        return entry.address
    }

    func fetchAccountNumber(_ address: String) async throws -> THORChainAccountValue? {
        let response = try await httpClient.request(
            mainnet(.accountNumber(address: address)),
            responseType: THORChainAccountNumberResponse.self
        )
        return response.data.result.value
    }

    func fetchSwapQuotes(
        address: String,
        fromAsset: String,
        toAsset: String,
        amount: String,
        interval: Int,
        streamingQuantity: Int,
        liquidityToleranceBps: Int,
        referredCode: String,
        vultTierDiscount: Int
    ) async throws -> ThorchainSwapQuote {
        let (affiliates, affiliateBps) = ThorchainService.affiliateParams(
            referredCode: referredCode,
            discountBps: vultTierDiscount
        )

        let target = mainnet(.swapQuote(
            fromAsset: fromAsset,
            toAsset: toAsset,
            amount: amount,
            destination: address,
            streamingInterval: String(interval),
            streamingQuantity: streamingQuantity > 0 ? String(streamingQuantity) : nil,
            affiliates: affiliates,
            affiliateBps: affiliateBps,
            liquidityToleranceBps: liquidityToleranceBps > 0 ? String(liquidityToleranceBps) : nil
        ))

        // THORChain returns a typed swap-error body (sometimes with HTTP 200,
        // sometimes 4xx) for invalid quotes. Fetch raw bytes once and try the
        // success shape first, falling back to the error shape — avoids a
        // second round-trip on the error path.
        do {
            let raw = try await httpClient.request(target)
            return try Self.decodeSwapQuoteOrError(from: raw.data)
        } catch let error as HTTPError {
            if case .statusCode(_, let data?) = error,
               let swapError = try? JSONDecoder().decode(ThorchainSwapError.self, from: data) {
                throw swapError
            }
            throw error
        }
    }

    static func decodeSwapQuoteOrError(from data: Data) throws -> ThorchainSwapQuote {
        if let quote = try? JSONDecoder().decode(ThorchainSwapQuote.self, from: data) {
            return quote
        }
        throw try JSONDecoder().decode(ThorchainSwapError.self, from: data)
    }

    func fetchFeePrice() async throws -> UInt64 {
        let cacheKey = "thorchain-fee-price"
        if let cachedData = Utils.getCachedData(cacheKey: cacheKey, cache: cacheFeePrice, timeInSeconds: 60*5) {
            return UInt64(cachedData.native_tx_fee_rune) ?? 0
        }

        let response = try await httpClient.request(
            mainnet(.networkInfo),
            responseType: ThorchainNetworkInfo.self
        )
        let thorchainNetworkInfo = response.data
        self.cacheFeePrice.set(cacheKey, (data: thorchainNetworkInfo, timestamp: Date()))
        return UInt64(thorchainNetworkInfo.native_tx_fee_rune) ?? 0
    }

    /// Fetch THORChain inbound addresses (halt flags + gas rates), cached 5 min.
    /// Pass `bypassCache: true` for the sign-time halt re-check, which must never
    /// read or write the cache — the decision needs a fresh, live value.
    func fetchThorchainInboundAddress(bypassCache: Bool = false) async -> [InboundAddress] {
        do {
            return try await fetchThorchainInboundAddressOrThrow(bypassCache: bypassCache)
        } catch {
            logger.warning("JSON decoding error: \(error.localizedDescription)")
            return []
        }
    }

    /// Throwing variant of `fetchThorchainInboundAddress` for the sign-time
    /// fund-safety gate, which must fail CLOSED: a transport/decode failure has
    /// to propagate so the gate can block signing instead of misreading an empty
    /// list as "not halted". The fail-soft `fetchThorchainInboundAddress` wraps
    /// this for screen-level / FunctionCall callers that prefer an empty fallback.
    func fetchThorchainInboundAddressOrThrow(bypassCache: Bool = false) async throws -> [InboundAddress] {
        let cacheKey = "thorchain-inbound-address"

        if !bypassCache,
           let cachedData = Utils.getCachedData(
               cacheKey: cacheKey,
               cache: cacheInboundAddresses,
               timeInSeconds: 60 * 5
           ) {
            return cachedData
        }

        let response = try await httpClient.request(
            mainnet(.inboundAddresses),
            responseType: [InboundAddress].self
        )
        let inboundAddresses = response.data
        if !bypassCache {
            self.cacheInboundAddresses.set(cacheKey, (data: inboundAddresses, timestamp: Date()))
        }
        return inboundAddresses
    }

    func getTHORChainChainID() async throws -> String {
        if !network.isEmpty {
            logger.debug("network id: \(self.network)")
            return network
        }
        let response = try await httpClient.request(
            mainnet(.networkStatus),
            responseType: THORChainNetworkStatus.self
        )
        network = response.data.result.node_info.network
        return response.data.result.node_info.network
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
                    self.logger.warning("fail to get thorchain id \(error.localizedDescription)")
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

    /// Builds `(affiliate, affiliateBps)` query params for THORChain swap quotes.
    /// THORChain supports nested affiliates: when a referral code is present,
    /// we emit two entries joined by `/` so the upstream quote splits the fee.
    /// Returns `(nil, nil)` if no affiliate entry should be sent.
    static func affiliateParams(referredCode: String, discountBps: Int) -> (String?, String?) {
        if !referredCode.isEmpty {
            let feeRate = THORChainSwaps.discountedAffiliateBps(baseBps: THORChainSwaps.referredAffiliateFeeRateBp, discountBps: discountBps)
            let addresses = "\(referredCode)/\(THORChainSwaps.affiliateFeeAddress)"
            let bps = "\(THORChainSwaps.referredUserFeeRateBp)/\(feeRate)"
            return (addresses, bps)
        } else {
            let feeRate = THORChainSwaps.discountedAffiliateBps(baseBps: THORChainSwaps.affiliateFeeRateBp, discountBps: discountBps)
            return (THORChainSwaps.affiliateFeeAddress, "\(feeRate)")
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
        if let cachedData = Utils.getCachedData(cacheKey: cacheKey, cache: cacheAssetPrices, timeInSeconds: 60*5) {
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
            logger.warning("Error in getAssetPriceInUSD: \(error.localizedDescription)")
            return 0.0
        }
    }

    private func fetchAssetPrice(assetName: String) async throws -> Double {
        let response = try await httpClient.request(
            mainnet(.poolInfo(asset: assetName)),
            responseType: THORChainPoolResponse.self
        )

        // Convert from 8 decimal places to a decimal value
        guard let priceValue = Double(response.data.assetTorPrice) else {
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

    /// A single merge account entry as returned by the RUJIRA GraphQL API,
    /// keyed by the canonical symbol (e.g. "KUJI", "RKUJI", "FUZN").
    struct RujiMergeAccount {
        let symbol: String
        let shares: String
        let sizeAmount: String
    }

    /// Structure representing a RUJI Stake balance result
    struct RujiStakeBalance {
        let stakeAmount: BigInt
        let stakeTicker: String
        let rewardsAmount: BigInt
        let rewardsTicker: String

        static let empty = RujiStakeBalance(stakeAmount: .zero, stakeTicker: "", rewardsAmount: .zero, rewardsTicker: "")
    }

    /// Fetch every merge account tied to the given THORChain address.
    /// - Parameter thorAddr: The THORChain address to query.
    /// - Returns: All merge accounts keyed by their canonical asset symbol.
    func fetchAllRujiMergeBalances(thorAddr: String) async throws -> [RujiMergeAccount] {
        let id = "Account:\(thorAddr)".data(using: .utf8)?.base64EncodedString() ?? ""
        let query = String(format: Self.mergedAssetsQuery, id)

        let response = try await httpClient.request(
            mainnet(.rujiGraphQL(query: query)),
            responseType: AccountRootData.self
        )

        return response.data.data.node?.merge?.accounts.map { account in
            RujiMergeAccount(
                symbol: account.pool.mergeAsset.metadata.symbol,
                shares: account.shares,
                sizeAmount: account.size.amount
            )
        } ?? []
    }

    /// Fetch merged RUJI balance for a specific token.
    /// - Parameters:
    ///   - thorAddr: The THORChain address to query.
    ///   - tokenSymbol: The token symbol to check (e.g. "THOR.KUJI", "KUJI").
    /// - Returns: The matching balance or a zero balance when no position exists.
    func fetchRujiMergeBalance(thorAddr: String, tokenSymbol: String) async throws -> RujiBalance {
        let accounts = try await fetchAllRujiMergeBalances(thorAddr: thorAddr)
        let target = Self.normalizeRujiSymbol(tokenSymbol)

        guard let match = accounts.first(where: { Self.normalizeRujiSymbol($0.symbol) == target }) else {
            let available = accounts.map(\.symbol).joined(separator: ", ")
            logger.warning("No RUJI merge account matched \(tokenSymbol, privacy: .public); available symbols: [\(available, privacy: .public)]")
            return RujiBalance(ruji: 0, shares: "0", price: 0)
        }

        let shares = match.shares
        let ruji = Decimal(string: match.sizeAmount) ?? 0
        let sharesDecimal = Decimal(string: shares) ?? 1
        let price = sharesDecimal > 0 ? ruji / sharesDecimal : 0

        return RujiBalance(ruji: ruji, shares: shares, price: price)
    }

    /// Normalize a RUJI merge token identifier (e.g. `"THOR.KUJI"`, `"kuji"`, `"KUJI"`)
    /// into a canonical uppercase ticker suitable for equality comparisons.
    static func normalizeRujiSymbol(_ symbol: String) -> String {
        var normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized.hasPrefix("THOR.") {
            normalized.removeFirst("THOR.".count)
        }
        return normalized
    }

    func fetchRujiStakeBalance(thorAddr: String) async throws -> RujiStakeBalance {
        let id = "Account:\(thorAddr)".data(using: .utf8)?.base64EncodedString() ?? ""
        let query = String(format: Self.stakeQuery, id)

        let response = try await httpClient.request(
            mainnet(.rujiGraphQL(query: query)),
            responseType: AccountRootData.self
        )

        guard let stake = response.data.data.node?.stakingV2?.first else {
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
                let poolResponse = try await httpClient.request(
                    mainnet(.poolLiquidityProvider(asset: pool.asset, address: address))
                )

                // 404 means no position on this pool — TargetType validation accepts it.
                if poolResponse.response.statusCode == 404 {
                    continue
                }

                // Try to decode as pool LP response
                if let lpResponse = try? JSONDecoder().decode(ThorchainPoolLPResponse.self, from: poolResponse.data) {
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
        let response = try await httpClient.request(
            mainnet(.poolInfo(asset: asset)),
            responseType: ThorchainPool.self
        )
        return response.data
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
            let response = try await httpClient.request(
                mainnet(.pools),
                responseType: [ThorchainPool].self
            )
            let pools = response.data

            // Filter only available pools
            let availablePools = pools.filter { $0.status == "Available" }

            // Cache the result
            cacheLPPools.set(cacheKey, (data: availablePools, timestamp: Date()))

            return availablePools
        }
    }

    /// Fetch the canonical THORChain secured-asset universe from
    /// `/thorchain/securedassets`. Each entry is the uppercase dash-notation
    /// denom (e.g. `ETH-USDC-0X…`) plus its `supply`/`depth`. Cached for 5
    /// minutes and retried like `fetchLPPools`. This is the source of truth for
    /// the discovery catalog — every pooled/securable asset has a secured form.
    func fetchSecuredAssets() async throws -> [ThorchainSecuredAsset] {
        let cacheKey = "secured_assets"
        let cacheExpirationMinutes = 5.0

        if let cached = cacheSecuredAssets.get(cacheKey),
           Date().timeIntervalSince(cached.timestamp) < cacheExpirationMinutes * 60 {
            return cached.data
        }

        return try await withRetry(maxAttempts: 3) {
            let response = try await httpClient.request(
                mainnet(.securedAssets),
                responseType: [ThorchainSecuredAsset].self
            )
            let assets = response.data
            cacheSecuredAssets.set(cacheKey, (data: assets, timestamp: Date()))
            return assets
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
    /// Per-pool trading-halt flag from thornode `/thorchain/pools`. Optional so
    /// the single-pool `/thorchain/pool/{asset}` decode path stays unaffected.
    let tradingHalted: Bool?

    enum CodingKeys: String, CodingKey {
        case status
        case asset
        case decimals
        case balanceAsset = "balance_asset"
        case balanceRune = "balance_rune"
        case assetTorPrice = "asset_tor_price"
        case tradingHalted = "trading_halted"
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

    func getCosmosTokenMetadata(denom: String) async throws -> CosmosTokenMetadata {
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
        do {
            let response = try await httpClient.request(
                mainnet(.denomMetadata(denom: denom)),
                responseType: MetadataResponse.self
            )
            return response.data.metadata
        } catch {
            return nil
        }
    }

    private func attemptListFetch(denom: String) async throws -> DenomMetadata? {
        do {
            let response = try await httpClient.request(
                mainnet(.allDenomMetadata),
                responseType: MetadatasResponse.self
            )
            if let metadatas = response.data.metadatas {
                for metadata in metadatas where metadata.base == denom {
                    return metadata
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
