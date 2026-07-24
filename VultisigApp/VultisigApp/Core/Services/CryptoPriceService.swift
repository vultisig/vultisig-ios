import Foundation
import OSLog
import SwiftUI

struct CoinGeckoCoin: Decodable {
    let id: String
    let symbol: String
    let name: String
    let platforms: [String: String]
}

struct MAYAChainPoolResponse: Decodable {
    let balanceCacao: String
    let balanceAsset: String

    enum CodingKeys: String, CodingKey {
        case balanceCacao = "balance_cacao"
        case balanceAsset = "balance_asset"
    }
}

class CacheCoinGeckoCoin {
    let coins: [CoinGeckoCoin]
    let timestamp: Date

    init(coins: [CoinGeckoCoin], timestamp: Date) {
        self.coins = coins
        self.timestamp = timestamp
    }
}

/// TargetType for the price/coin-metadata endpoints used by CryptoPriceService.
/// Three distinct hosts (vultisigApiProxy for CoinGecko-proxy + LiFi + MAYAChain
/// node) are modelled as per-case `baseURL`.
enum CryptoPriceAPI: TargetType {
    case coinGeckoCoinsList
    case pricesByIds(ids: String, currencies: String)
    case pricesByContract(network: String, addresses: String, currencies: String)
    case lifiTokenPrice(network: String, address: String)
    case mayaChainPool(asset: String)

    var baseURL: URL {
        switch self {
        case .coinGeckoCoinsList, .pricesByIds, .pricesByContract:
            return URL(string: Endpoint.vultisigApiProxy)!
        case .lifiTokenPrice:
            return URL(string: "https://li.quest")!
        case .mayaChainPool:
            return URL(string: "https://mayanode.mayachain.info")!
        }
    }

    var path: String {
        switch self {
        case .coinGeckoCoinsList:
            return "/coingeicko/api/v3/coins/list"
        case .pricesByIds:
            return "/coingeicko/api/v3/simple/price"
        case .pricesByContract(let network, _, _):
            return "/coingeicko/api/v3/simple/token_price/\(network.lowercased())"
        case .lifiTokenPrice:
            return "/v1/token"
        case .mayaChainPool(let asset):
            let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
            let encodedAsset = asset.addingPercentEncoding(withAllowedCharacters: allowed) ?? asset
            return "/mayachain/pool/\(encodedAsset)"
        }
    }

    var method: HTTPMethod { .get }

    var task: HTTPTask {
        switch self {
        case .coinGeckoCoinsList:
            return .requestParameters([
                "include_platform": "true",
                "status": "active"
            ], .urlEncoding)
        case .pricesByIds(let ids, let currencies):
            return .requestParameters([
                "ids": ids,
                "vs_currencies": currencies
            ], .urlEncoding)
        case .pricesByContract(_, let addresses, let currencies):
            return .requestParameters([
                "contract_addresses": addresses,
                "vs_currencies": currencies
            ], .urlEncoding)
        case .lifiTokenPrice(let network, let address):
            return .requestParameters([
                "chain": network.lowercased(),
                "token": address
            ], .urlEncoding)
        case .mayaChainPool:
            return .requestPlain
        }
    }
}

public class CryptoPriceService: ObservableObject {
    private let logger = Logger(subsystem: "com.vultisig.app", category: "crypto-price-service")

    struct ResolvedSources {
        let providerIds: [String]
        let contracts: [Chain: [String]]
    }

    public static let shared = CryptoPriceService()
    private let cache: NSCache<NSString, CacheCoinGeckoCoin> = NSCache()
    private let coinGeckoListCacheKey: NSString = "coingecko-list"
    private let httpClient: HTTPClientProtocol

    private init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func fetchPrices(coins: [CoinMeta]) async throws {
        let sources = resolveSources(coins: coins)

        if !sources.providerIds.isEmpty {
            try await fetchPrices(ids: sources.providerIds)
        }

        if !sources.contracts.isEmpty {
            for (chain, contracts) in sources.contracts {
                try await fetchPrices(contracts: contracts, chain: chain, coins: coins)
            }
        }
    }

    func fetchPrice(coin: Coin) async throws {
        try await fetchPrices(coins: [coin])

        await refresh(coins: [coin])
    }

    func resolvePriceProviderID(symbol: String, contract: String) async throws -> String? {
        let cachedList = self.cache.object(forKey: coinGeckoListCacheKey)
        // good to cache it for an hour , it doesn't change much
        if let cachedList = cachedList, Date().timeIntervalSince(cachedList.timestamp) < 3600 {
            let target = cachedList.coins.first { $0.symbol.lowercased() == symbol.lowercased() && $0.platforms.values.contains(contract)}
            return target?.id
        }
        let response = try await httpClient.request(
            CryptoPriceAPI.coinGeckoCoinsList,
            responseType: [CoinGeckoCoin].self
        )
        let coinsList = response.data
        if !coinsList.isEmpty {
            self.cache.setObject(CacheCoinGeckoCoin(coins: coinsList, timestamp: Date()), forKey: coinGeckoListCacheKey)
        }
        let target = coinsList.first { $0.symbol.lowercased() == symbol.lowercased() && $0.platforms.values.contains(contract)}
        return target?.id
    }
}

extension CryptoPriceService {
    /// Pure computation for the MAYAChain pool-derived USD price of a non-CACAO Maya asset.
    /// Internal access so unit tests can validate the math without exercising the live mayanode endpoint.
    func calculateMayaPoolPrice(pool: MAYAChainPoolResponse, cacaoPriceUSD: Double, coins: [CoinMeta], assetName: String) -> Double {
        guard let balanceCacao = Double(pool.balanceCacao),
              let balanceAsset = Double(pool.balanceAsset),
              balanceAsset > 0 else {
            return 0.0
        }

        let ticker = assetName.components(separatedBy: ".").last ?? ""
        let assetDecimals = coins.first(where: {
            $0.chain == .mayaChain && $0.ticker.uppercased() == ticker
        })?.decimals ?? 4

        let cacaoDecimals: Double = 10
        let cacaoNormalized = balanceCacao / pow(10, cacaoDecimals)
        let assetNormalized = balanceAsset / pow(10, Double(assetDecimals))
        let priceInCacao = cacaoNormalized / assetNormalized

        return priceInCacao * cacaoPriceUSD
    }
}

private extension CryptoPriceService {

    @MainActor func refresh(coins: [Coin]) {
        for coin in coins {
            coin.objectWillChange.send()
        }
    }

    func fetchPrices(coins: [Coin]) async throws {
        try await fetchPrices(coins: coins.map { $0.toCoinMeta() })
    }

    func resolveSources(coins: [CoinMeta]) -> ResolvedSources {
        var providerIds: [String] = []
        var contracts: [Chain: [String]] = [:]

        for coin in coins {
            switch RateProvider.cryptoId(for: coin) {
            case .priceProvider(let id):
                providerIds.append(id)
            case .contract(let id):
                contracts[coin.chain, default: []].append(id)
            }
        }

        return ResolvedSources(providerIds: providerIds, contracts: contracts)
    }

    func fetchPrices(ids: [String]) async throws {
        let idsQuery = ids
            .filter { !$0.isEmpty }
            .joined(separator: ",")

        let currencies = SettingsCurrency.allCases
            .map { $0.rawValue }
            .joined(separator: ",")

        do {
            let response = try await httpClient.request(
                CryptoPriceAPI.pricesByIds(ids: idsQuery, currencies: currencies),
                responseType: [String: [String: Double]].self
            )
            try await RateProvider.shared.save(rates: mapRates(response: response.data))
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled {
                logger.debug("Price fetch cancelled")
            }
            throw error
        }
    }

    func fetchPrices(contracts: [String], chain: Chain, coins: [CoinMeta] = []) async throws {

        if chain == .solana {

            var rates: [Rate] = []
            for contract in contracts {
                let decimals = coins.first(where: {
                    $0.chain == .solana && $0.contractAddress == contract
                })?.decimals ?? 6

                let poolPrice = await SolanaService.getTokenUSDValue(contractAddress: contract, decimals: decimals)
                let poolRate: Rate = .init(fiat: "usd", crypto: contract, value: poolPrice)
                rates.append(poolRate)
            }

            try await RateProvider.shared.save(rates: rates)

        } else if chain == .sui {

            var rates: [Rate] = []
            for contract in contracts {
                // Try to find the coin metadata to get proper decimals
                guard let tokenMeta = TokensStore.TokenSelectionAssets.first(where: { asset in
                    asset.chain == .sui && asset.contractAddress.lowercased() == contract.lowercased()
                }) else {
                    // Skip tokens without metadata instead of using default decimals
                    logger.warning("No metadata found for SUI token \(contract), skipping price fetch")
                    continue
                }

                let decimals = tokenMeta.decimals

                // Use the enhanced method with decimals
                let poolPrice = await SuiService.getTokenUSDValue(contractAddress: contract, decimals: decimals)
                let poolRate: Rate = .init(fiat: "usd", crypto: contract, value: poolPrice)
                rates.append(poolRate)
            }

            try await RateProvider.shared.save(rates: rates)

        } else if chain == .mayaChain {

            let rates = await fetchMayaChainPoolPrices(contracts: contracts, coins: coins)
            try await RateProvider.shared.save(rates: rates)

        } else if chain == .thorChain || chain == .thorChainChainnet || chain == .thorChainStagenet {

            let thorService = ThorchainServiceFactory.getService(for: chain)
            var rates: [Rate] = []
            for contract in contracts {

                let yieldTokens = TokensStore.TokenSelectionAssets.filter({ $0.chain == chain && ( $0.ticker == "yRUNE" || $0.ticker == "yTCY" || $0.ticker == "ybRUNE") }).map({$0.contractAddress})

                if yieldTokens.contains(contract) {
                    let price = await thorService.fetchYieldTokenPrice(for: contract)
                    let rate: Rate = .init(fiat: "usd", crypto: contract, value: price ?? 0.0)
                    rates.append(rate)
                } else {
                    var sanitisedContract = contract.uppercased().replacingOccurrences(of: "X/", with: "")

                    // Handle staking assets mappings to their underlying asset for price
                    if sanitisedContract.starts(with: "STAKING-") {
                        sanitisedContract = sanitisedContract.replacingOccurrences(of: "STAKING-", with: "")
                    }

                    // Ensure we have the THOR. prefix for the pool lookup
                    let assetName = sanitisedContract.contains(".") ? sanitisedContract : "THOR.\(sanitisedContract)"

                    let poolPrice = await thorService.getAssetPriceInUSD(assetName: assetName)
                    let poolRate: Rate = .init(fiat: "usd", crypto: contract, value: poolPrice)
                    rates.append(poolRate)
                }
            }

            try await RateProvider.shared.save(rates: rates)

        } else {

            let currencies = SettingsCurrency.allCases
                .map { $0.rawValue }
                .joined(separator: ",")

            let addresses = contracts.joined(separator: ",")
            let response = try await httpClient.request(
                CryptoPriceAPI.pricesByContract(
                    network: coinGeckoPlatform(chain: chain),
                    addresses: addresses,
                    currencies: currencies
                ),
                responseType: [String: [String: Double]].self
            ).data

            let contractsNotFoundOnCoingecko = contracts.filter { !response.keys.contains($0) }

            var rates = mapRates(response: response)

            // now lets try to find the price for the notFoundPricesOnCoingecko
            for contract in contractsNotFoundOnCoingecko {
                if let lifiRate = try await fetchLifiTokenPrice(contract: contract, chain: chain) {
                    rates.append(lifiRate)
                }
            }

            try await RateProvider.shared.save(rates: rates)
        }
    }

    func fetchLifiTokenPrice(contract: String, chain: Chain) async throws -> Rate? {
        guard let chainID = chain.chainID else {
            logger.warning("No LiFi chain ID for \(chain.ticker), skipping price fetch for \(contract)")
            return nil
        }

        let response = try await httpClient.request(
            CryptoPriceAPI.lifiTokenPrice(network: String(chainID), address: contract)
        )
        guard let priceUsd = Utils.extractResultFromJson(fromData: response.data, path: "priceUSD") as? String,
              let price = Double(priceUsd) else {
            logger.warning("No LiFi price found for \(contract) on chain \(chain.ticker)")
            return nil
        }

        return .init(fiat: "usd", crypto: contract, value: price)
    }

    func mapRates(response: [String: [String: Double]]) -> [Rate] {
        let rates: [[Rate]] = response.map { crypto, map in
            return SettingsCurrency.allCases.compactMap { currency in
                let fiat = currency.rawValue.lowercased()
                guard let value = map[fiat] else { return nil }
                return Rate(fiat: fiat, crypto: crypto, value: value)
            }
        }

        return Array(rates.joined())
    }

    func fetchMayaChainPoolPrices(contracts: [String], coins: [CoinMeta]) async -> [Rate] {
        if RateProvider.shared.rate(for: TokensStore.cacao) == nil {
            logger.info("CACAO price not cached, fetching before MAYAChain pool pricing")
            try? await fetchPrices(ids: [TokensStore.cacao.priceProviderId])
        }

        guard let cacaoRate = RateProvider.shared.rate(for: TokensStore.cacao) else {
            logger.warning("CACAO price unavailable, cannot derive MAYAChain pool prices")
            return []
        }

        let cacaoPriceUSD = cacaoRate.value

        var rates: [Rate] = []
        for contract in contracts {
            let assetName = "MAYA.\(contract.uppercased())"
            if let price = await fetchMayaChainPoolPrice(assetName: assetName, cacaoPriceUSD: cacaoPriceUSD, coins: coins) {
                rates.append(Rate(fiat: "usd", crypto: contract, value: price))
            }
        }

        return rates
    }

    func fetchMayaChainPoolPrice(assetName: String, cacaoPriceUSD: Double, coins: [CoinMeta]) async -> Double? {
        do {
            let response = try await httpClient.request(
                CryptoPriceAPI.mayaChainPool(asset: assetName),
                responseType: MAYAChainPoolResponse.self
            )
            return calculateMayaPoolPrice(pool: response.data, cacaoPriceUSD: cacaoPriceUSD, coins: coins, assetName: assetName)
        } catch {
            logger.warning("Failed to fetch MAYAChain pool price for \(assetName): \(error.localizedDescription)")
            return nil
        }
    }

    private func coinGeckoPlatform(chain: Chain) -> String {
        switch chain {
        case .ethereum, .ethereumSepolia:
            return "ethereum"
        case .avalanche:
            return "avalanche"
        case .base:
            return "base"
        case .blast:
            return "blast"
        case .arbitrum:
            return "arbitrum-one"
        case .polygon, .polygonV2:
            return "polygon-pos"
        case .optimism:
            return "optimistic-ethereum"
        case .bscChain:
            return "binance-smart-chain"
        case .zksync:
            return "zksync"
        case .mantle:
            return "mantle"
        case .robinhood:
            return "robinhood"
        case .thorChain, .thorChainChainnet, .thorChainStagenet, .solana, .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash, .gaiaChain, .kujira, .mayaChain, .cronosChain, .polkadot, .dydx, .sui, .ton, .osmosis, .terra, .terraClassic, .noble, .ripple, .akash, .tron, .zcash, .cardano, .hyperliquid, .sei, .qbtc, .bittensor:
            return .empty
        }
    }
}
