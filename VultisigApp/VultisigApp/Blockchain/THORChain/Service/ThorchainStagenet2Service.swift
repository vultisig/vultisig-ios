//
//  ThorchainStagenetService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 12/02/2026.
//

import Foundation
import BigInt

class ThorchainStagenetService: ThorchainSwapProvider {
    var network: String = ""
    static let shared = ThorchainStagenetService()

    private let httpClient: HTTPClientProtocol = HTTPClient()

    private var cacheFeePrice = ThreadSafeDictionary<String, (data: ThorchainNetworkInfo, timestamp: Date)>()
    private var cacheInboundAddresses = ThreadSafeDictionary<String, (data: [InboundAddress], timestamp: Date)>()
    private var cacheAssetPrices = ThreadSafeDictionary<String, (data: Double, timestamp: Date)>()
    private var cacheLPPools = ThreadSafeDictionary<String, (data: [ThorchainPool], timestamp: Date)>()
    private var cacheLPPositions = ThreadSafeDictionary<String, (data: [ThorchainLPPosition], timestamp: Date)>()

    private init() {}

    // MARK: - Helpers

    /// The environment for this service is `.stagenet` — Vultisig's internal
    /// "Stagenet-2" which actually hits `stagenet-thornode.thorchain.network`.
    private let env: ThorchainStagenetAPI.Environment = .stagenet

    // MARK: - Public API

    func fetchBalances(_ address: String) async throws -> [CosmosBalance] {
        let response = try await httpClient.request(
            ThorchainStagenetAPI.balances(env: env, address: address),
            responseType: CosmosBalanceResponse.self
        )
        return response.data.balances
    }

    func fetchTokens(_ address: String) async throws -> [CoinMeta] {
        let balances: [CosmosBalance] = try await fetchBalances(address)
        var coinMetaList = [CoinMeta]()
        // Native RUNE is the chain's main asset and is added separately;
        // including it here would surface a duplicate non-native row.
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

            let localAsset = TokensStore.TokenSelectionAssets.first(where: { $0.ticker.uppercased() == ticker.uppercased() })

            if ticker.range(of: "yrune", options: [.caseInsensitive, .anchored]) == nil &&
                ticker.range(of: "ytcy", options: [.caseInsensitive, .anchored]) == nil &&
                ticker.range(of: "stcy", options: [.caseInsensitive, .anchored]) == nil &&
                ticker.range(of: "sruji", options: [.caseInsensitive, .anchored]) == nil {
                ticker = ticker.uppercased()
            }

            let finalLogo = localAsset?.logo ?? logo

            let coinMeta = CoinMeta(
                chain: .thorChainStagenet,
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
            ThorchainStagenetAPI.resolveTNS(name: name),
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
            ThorchainStagenetAPI.accountNumber(env: env, address: address),
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
        toleranceBps: Int,
        referredCode: String,
        vultTierDiscount: Int
    ) async throws -> ThorchainSwapQuote {
        let (affiliates, affiliateBps) = ThorchainService.affiliateParams(
            referredCode: referredCode,
            discountBps: vultTierDiscount
        )

        let target = ThorchainStagenetAPI.swapQuote(
            env: env,
            fromAsset: fromAsset,
            toAsset: toAsset,
            amount: amount,
            destination: address,
            streamingInterval: String(interval),
            streamingQuantity: streamingQuantity > 0 ? String(streamingQuantity) : nil,
            affiliates: affiliates,
            affiliateBps: affiliateBps,
            toleranceBps: toleranceBps > 0 ? String(toleranceBps) : nil
        )

        do {
            let raw = try await httpClient.request(target)
            return try ThorchainService.decodeSwapQuoteOrError(from: raw.data)
        } catch let error as HTTPError {
            if case .statusCode(_, let data?) = error,
               let swapError = try? JSONDecoder().decode(ThorchainSwapError.self, from: data) {
                throw swapError
            }
            throw error
        }
    }

    func fetchFeePrice() async throws -> UInt64 {
        let cacheKey = "thorchain-stagenet2-fee-price"
        if let cachedData = Utils.getCachedData(cacheKey: cacheKey, cache: cacheFeePrice, timeInSeconds: 60*5) {
            return UInt64(cachedData.native_tx_fee_rune) ?? 0
        }

        let response = try await httpClient.request(
            ThorchainStagenetAPI.networkInfo(env: env),
            responseType: ThorchainNetworkInfo.self
        )
        self.cacheFeePrice.set(cacheKey, (data: response.data, timestamp: Date()))
        return UInt64(response.data.native_tx_fee_rune) ?? 0
    }

    func fetchThorchainInboundAddress(bypassCache: Bool = false) async -> [InboundAddress] {
        do {
            let cacheKey = "thorchain-stagenet2-inbound-address"

            if !bypassCache,
               let cachedData = Utils.getCachedData(
                   cacheKey: cacheKey,
                   cache: cacheInboundAddresses,
                   timeInSeconds: 60 * 5
               ) {
                return cachedData
            }

            let response = try await httpClient.request(
                ThorchainStagenetAPI.inboundAddresses(env: env),
                responseType: [InboundAddress].self
            )
            if !bypassCache {
                self.cacheInboundAddresses.set(cacheKey, (data: response.data, timestamp: Date()))
            }
            return response.data
        } catch {
            return []
        }
    }

    func getTHORChainChainID() async throws -> String {
        if !network.isEmpty {
            return network
        }
        let response = try await httpClient.request(
            ThorchainStagenetAPI.networkStatus(env: env),
            responseType: THORChainNetworkStatus.self
        )
        network = response.data.result.node_info.network
        return network
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
                    // Expected failure during network init
                }
                group.leave()
            }
        }
        group.wait()
        return network
    }

    func broadcastTransaction(jsonString: String) async -> Result<String, Error> {
        guard let jsonData = jsonString.data(using: .utf8) else {
            return .failure(HelperError.runtimeError("fail to convert input json to data"))
        }

        do {
            let raw = try await httpClient.request(ThorchainStagenetAPI.broadcast(env: env, body: jsonData))
            let response = try JSONDecoder().decode(CosmosTransactionBroadcastResponse.self, from: raw.data)
            if let code = response.txResponse?.code, code == 0 || code == 19 {
                if let txHash = response.txResponse?.txhash {
                    return .success(txHash)
                }
            }
            return .failure(HelperError.runtimeError(String(data: raw.data, encoding: .utf8) ?? "Unknown error"))
        } catch HTTPError.statusCode(let code, let data) {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
            return .failure(HelperError.runtimeError("status code:\(code), \(body)"))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Errors
    enum Errors: Error {
        case tnsEntryNotFound
        case invalidURL
        case invalidPriceFormat
        case invalidResponse
        case apiError(String)
    }
}

// MARK: - THORChain Stagenet-2 Pool Prices & Token Metadata
extension ThorchainStagenetService {
    // swiftlint:disable:next unused_parameter async_without_await
    func fetchYieldTokenPrice(for contract: String) async -> Double? {
        return nil
    }

    func getAssetPriceInUSD(assetName: String) async -> Double {
        let cacheKey = "\(assetName.lowercased())-stagenet2-price"

        if let cachedData = Utils.getCachedData(cacheKey: cacheKey, cache: cacheAssetPrices, timeInSeconds: 60*5) {
            return cachedData
        }

        do {
            let price = try await fetchAssetPrice(assetName: assetName)
            if price > 0 {
                self.cacheAssetPrices.set(cacheKey, (data: price, timestamp: Date()))
            }
            return price
        } catch {
            return 0.0
        }
    }

    func assetExistsInPools(assetName: String) async -> Bool {
        do {
            _ = try await fetchAssetPrice(assetName: assetName)
            return true
        } catch {
            return false
        }
    }

    func formatAssetName(chain: Chain, symbol: String) -> String {
        let chainCode = (chain == .thorChainChainnet || chain == .thorChainStagenet) ? "THOR" : chain.rawValue.uppercased()
        let assetSymbol = symbol.uppercased()
        return "\(chainCode).\(assetSymbol)"
    }

    private func fetchAssetPrice(assetName: String) async throws -> Double {
        let response = try await httpClient.request(
            ThorchainStagenetAPI.poolInfo(env: env, asset: assetName),
            responseType: THORChainPoolResponse.self
        )

        guard let priceValue = Double(response.data.assetTorPrice) else {
            throw Errors.invalidPriceFormat
        }

        return priceValue / 100_000_000
    }

    private func getCosmosTokenMetadata(denom: String) async throws -> CosmosTokenMetadata {
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
                ThorchainStagenetAPI.denomMetadata(env: env, denom: denom),
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
                ThorchainStagenetAPI.allDenomMetadata(env: env),
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

// MARK: - THORChain Stagenet-2 LP Functionality
extension ThorchainStagenetService {

    func fetchLPPositions(runeAddress: String? = nil, assetAddress: String? = nil) async throws -> [ThorchainLPPosition] {
        let targetAddress = runeAddress ?? assetAddress
        guard let address = targetAddress else {
            throw HelperError.runtimeError("Either rune address or asset address must be provided")
        }

        let cacheKey = "lp_positions_stagenet2_\(address)"
        let cacheExpirationMinutes = 2.0

        if let cached = cacheLPPositions.get(cacheKey),
           Date().timeIntervalSince(cached.timestamp) < cacheExpirationMinutes * 60 {
            return cached.data
        }

        let pools = try await fetchLPPools()
        var allPositions: [ThorchainLPPosition] = []

        for pool in pools {
            do {
                let poolResponse = try await httpClient.request(
                    ThorchainStagenetAPI.poolLiquidityProvider(env: env, asset: pool.asset, address: address)
                )

                if poolResponse.response.statusCode == 404 {
                    continue
                }

                if let lpResponse = try? JSONDecoder().decode(ThorchainPoolLPResponse.self, from: poolResponse.data) {
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

                try await Task.sleep(nanoseconds: 100_000_000)

            } catch {
                continue
            }
        }

        cacheLPPositions.set(cacheKey, (data: allPositions, timestamp: Date()))

        return allPositions
    }

    func fetchPoolInfo(asset: String) async throws -> ThorchainPool {
        let response = try await httpClient.request(
            ThorchainStagenetAPI.poolInfo(env: env, asset: asset),
            responseType: ThorchainPool.self
        )
        return response.data
    }

    func fetchLPPools() async throws -> [ThorchainPool] {
        let cacheKey = "lp_pools_stagenet2"
        let cacheExpirationMinutes = 5.0

        if let cached = cacheLPPools.get(cacheKey),
           Date().timeIntervalSince(cached.timestamp) < cacheExpirationMinutes * 60 {
            return cached.data
        }

        return try await withRetry(maxAttempts: 3) {
            let response = try await httpClient.request(
                ThorchainStagenetAPI.pools(env: env),
                responseType: [ThorchainPool].self
            )
            let availablePools = response.data.filter { $0.status == "Available" }
            cacheLPPools.set(cacheKey, (data: availablePools, timestamp: Date()))
            return availablePools
        }
    }

    private func withRetry<T>(maxAttempts: Int = 3, retryDelay: TimeInterval = 1.0, operation: () async throws -> T) async throws -> T {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    let delay = retryDelay * pow(2.0, Double(attempt - 1))
                    try await Task.sleep(for: .seconds(delay))
                }
            }
        }

        throw lastError ?? HelperError.runtimeError("Unknown error after \(maxAttempts) attempts")
    }

    // MARK: - TCY Staking Methods (Not supported on Stagenet-2)
    // swiftlint:disable:next unused_parameter async_without_await
    func fetchTcyStakedAmount(address: String) async -> Decimal {
        return 0
    }
    // swiftlint:disable:next unused_parameter async_without_await
    func fetchTcyAutoCompoundAmount(address: String) async throws -> Decimal {
        return 0
    }
    // swiftlint:disable:next unused_parameter async_without_await
    func fetchMergeAccounts(address: String) async -> [MergeAccountResponse.ResponseData.Node.AccountMerge.MergeAccount] {
        return []
    }
}
