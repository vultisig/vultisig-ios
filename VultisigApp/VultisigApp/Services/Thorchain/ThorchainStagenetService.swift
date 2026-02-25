//
//  ThorchainChainnetService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/10/2025.
//

import Foundation
import BigInt

class ThorchainChainnetService: ThorchainSwapProvider {
    var network: String = ""
    static let shared = ThorchainChainnetService()

    private var cacheFeePrice = ThreadSafeDictionary<String, (data: ThorchainNetworkInfo, timestamp: Date)>()
    private var cacheInboundAddresses = ThreadSafeDictionary<String, (data: [InboundAddress], timestamp: Date)>()
    private var cacheAssetPrices = ThreadSafeDictionary<String, (data: Double, timestamp: Date)>()
    private var cacheLPPools = ThreadSafeDictionary<String, (data: [ThorchainPool], timestamp: Date)>()
    private var cacheLPPositions = ThreadSafeDictionary<String, (data: [ThorchainLPPosition], timestamp: Date)>()

    private init() {}

    func fetchBalances(_ address: String) async throws -> [CosmosBalance] {
        guard let url = URL(string: Endpoint.fetchAccountBalanceThorchainChainnet(address: address)) else {
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
                    ticker.range(of: "sruji", options: [.caseInsensitive, .anchored]) == nil {
                    ticker = ticker.uppercased()
                }

                // Use localAsset logo if available, otherwise use factory-generated logo
                let finalLogo = localAsset?.logo ?? logo

                let coinMeta = CoinMeta(
                    chain: .thorChainChainnet,
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
        guard let url = URL(string: Endpoint.fetchAccountNumberThorchainChainnet(address)) else {
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
            chain: .thorchainChainnet,
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
        let cacheKey = "thorchain-stagenet-fee-price"
        if let cachedData = Utils.getCachedData(cacheKey: cacheKey, cache: cacheFeePrice, timeInSeconds: 60*5) {
            return UInt64(cachedData.native_tx_fee_rune) ?? 0
        }

        let urlString = Endpoint.fetchThorchainChainnetNetworkInfoNineRealms
        let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        let thorchainNetworkInfo = try JSONDecoder().decode(ThorchainNetworkInfo.self, from: data)
        self.cacheFeePrice.set(cacheKey, (data: thorchainNetworkInfo, timestamp: Date()))
        return UInt64(thorchainNetworkInfo.native_tx_fee_rune) ?? 0
    }

    func fetchThorchainInboundAddress() async -> [InboundAddress] {
        do {
            let cacheKey = "thorchain-stagenet-inbound-address"

            if let cachedData = Utils.getCachedData(
                cacheKey: cacheKey,
                cache: cacheInboundAddresses,
                timeInSeconds: 60 * 5
            ) {
                return cachedData
            }

            let urlString = Endpoint.fetchThorchainChainnetInboundAddressesNineRealms
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
        let (data, _) = try await URLSession.shared.data(from: Endpoint.thorchainChainnetNetworkInfo)
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
                    _ =  try await self.getTHORChainChainID()
                } catch {
                    print("fail to get thorchain stagenet id \(error.localizedDescription)")
                }
                group.leave()
            }
        }
        group.wait()
        return network
    }

    func broadcastTransaction(jsonString: String) async -> Result<String, Error> {
        let url = URL(string: Endpoint.broadcastTransactionThorchainChainnet)!

        guard let jsonData = jsonString.data(using: .utf8) else {
            return .failure(HelperError.runtimeError("fail to convert input json to data"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (data, resp)  =  try await URLSession.shared.data(for: request)
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

// MARK: - THORChain Stagenet Pool Prices & Token Metadata
extension ThorchainChainnetService {
    // swiftlint:disable:next unused_parameter
    func fetchYieldTokenPrice(for contract: String) async -> Double? {
        // Stagenet doesn't support yield tokens (yRUNE, yTCY)
        // Return nil to indicate no price available
        return nil
    }

    func getAssetPriceInUSD(assetName: String) async -> Double {
        let cacheKey = "\(assetName.lowercased())-stagenet-price"

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
            print("Error in getAssetPriceInUSD: \(error.localizedDescription)")
            return 0.0
        }
    }

    private func fetchAssetPrice(assetName: String) async throws -> Double {
        let endpoint = Endpoint.fetchStagenetPoolInfo(asset: assetName)

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

        guard let priceValue = Double(poolResponse.assetTorPrice) else {
            throw Errors.invalidPriceFormat
        }

        let price = priceValue / 100_000_000
        return price
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
        let urlString = Endpoint.fetchThorchainChainnetDenomMetadata(denom: denom)

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
        let urlString = Endpoint.fetchThorchainChainnetAllDenomMetadata()

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

// MARK: - THORChain Stagenet LP Functionality
extension ThorchainChainnetService {

    func fetchLPPositions(runeAddress: String? = nil, assetAddress: String? = nil) async throws -> [ThorchainLPPosition] {
        let targetAddress = runeAddress ?? assetAddress
        guard let address = targetAddress else {
            throw HelperError.runtimeError("Either rune address or asset address must be provided")
        }

        let cacheKey = "lp_positions_stagenet_\(address)"
        let cacheExpirationMinutes = 2.0

        if let cached = cacheLPPositions.get(cacheKey),
           Date().timeIntervalSince(cached.timestamp) < cacheExpirationMinutes * 60 {
            return cached.data
        }

        let pools = try await fetchLPPools()
        var allPositions: [ThorchainLPPosition] = []

        for pool in pools {
            do {
                let poolUrlString = Endpoint.fetchThorchainChainnetPoolLiquidityProvider(asset: pool.asset, address: address)
                guard let poolUrl = URL(string: poolUrlString) else { continue }

                let (poolData, response) = try await URLSession.shared.data(for: get9RRequest(url: poolUrl))

                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 404 {
                    continue
                }

                if let lpResponse = try? JSONDecoder().decode(ThorchainPoolLPResponse.self, from: poolData) {
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
        let urlString = Endpoint.fetchStagenetPoolInfo(asset: asset)

        guard let url = URL(string: urlString) else {
            throw HelperError.runtimeError("Invalid URL")
        }

        let (data, _) = try await URLSession.shared.data(for: get9RRequest(url: url))
        let pool = try JSONDecoder().decode(ThorchainPool.self, from: data)
        return pool
    }

    func fetchLPPools() async throws -> [ThorchainPool] {
        let cacheKey = "lp_pools_stagenet"
        let cacheExpirationMinutes = 5.0

        if let cached = cacheLPPools.get(cacheKey),
           Date().timeIntervalSince(cached.timestamp) < cacheExpirationMinutes * 60 {
            return cached.data
        }

        return try await withRetry(maxAttempts: 3) {
            let urlString = Endpoint.fetchThorchainChainnetPools

            guard let url = URL(string: urlString) else {
                throw HelperError.runtimeError("Invalid URL")
            }

            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 10.0
            config.timeoutIntervalForResource = 15.0
            let session = URLSession(configuration: config)

            let (data, _) = try await session.data(for: get9RRequest(url: url))
            let pools = try JSONDecoder().decode([ThorchainPool].self, from: data)

            let availablePools = pools.filter { $0.status == "Available" }

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

    // MARK: - TCY Staking Methods (Not supported on Stagenet)
    // swiftlint:disable:next unused_parameter
    func fetchTcyStakedAmount(address: String) async -> Decimal {
        // Stagenet doesn't support TCY staking
        return 0
    }
    // swiftlint:disable:next unused_parameter
    func fetchTcyAutoCompoundAmount(address: String) async -> Decimal {
        // Stagenet doesn't support TCY auto-compound
        return 0
    }
    // swiftlint:disable:next unused_parameter
    func fetchMergeAccounts(address: String) async -> [MergeAccountResponse.ResponseData.Node.AccountMerge.MergeAccount] {
        // Stagenet doesn't support merge accounts
        return []
    }
}
