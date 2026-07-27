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
        MayaChainTokenPriceSource.calculatePoolPrice(
            pool: pool,
            cacaoPriceUSD: cacaoPriceUSD,
            coins: coins,
            assetName: assetName
        )
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
        try await CoinGeckoRates.fetchAndSaveByIds(ids, httpClient: httpClient, logger: logger)
    }

    func fetchPrices(contracts: [String], chain: Chain, coins: [CoinMeta] = []) async throws {
        let source = TokenPriceSourceRegistry.source(for: chain, httpClient: httpClient)
        let rates = try await source.prices(contracts: contracts, coins: coins)
        try await RateProvider.shared.save(rates: rates)
    }
}
