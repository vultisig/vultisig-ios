//
//  MarketDataAPI.swift
//  VultisigApp
//
//  CoinGecko market-data endpoints, served through the same
//  `Endpoint.vultisigApiProxy` host `CryptoPriceService` already uses — the
//  proxy holds the CoinGecko key server-side, so there is no new host and no
//  key on the client.
//

import Foundation

enum MarketDataAPI: TargetType {
    /// Price history for a coin identified by its CoinGecko id.
    case marketChartById(id: String, currency: String, days: String)
    /// Price history for a token identified by its contract on a CoinGecko
    /// asset platform — the route for tokens with no `priceProviderId`.
    case marketChartByContract(platform: String, contract: String, currency: String, days: String)
    /// Market cap / supply / all-time extremes for one coin.
    case markets(id: String, currency: String)

    var baseURL: URL {
        // Same literal `CryptoPriceAPI` force-unwraps: a compile-time constant
        // that is a valid absolute URL.
        URL(string: Endpoint.vultisigApiProxy)!
    }

    var path: String {
        switch self {
        case .marketChartById(let id, _, _):
            // `/coins/{id}` is case-sensitive upstream — `/coins/Bitcoin` is a
            // 404 while `/coins/bitcoin` is a 200 — and ids reach us from
            // `CoinMeta.priceProviderId`, custom-token resolution and fixtures,
            // not all of which are lower-cased. Normalising here removes a
            // whole class of silent 404s.
            return "/coingeicko/api/v3/coins/\(id.lowercased())/market_chart"
        case .marketChartByContract(let platform, let contract, _, _):
            return "/coingeicko/api/v3/coins/\(platform.lowercased())/contract/\(contract.lowercased())/market_chart"
        case .markets:
            return "/coingeicko/api/v3/coins/markets"
        }
    }

    var method: HTTPMethod { .get }

    var task: HTTPTask {
        switch self {
        case .marketChartById(_, let currency, let days),
             .marketChartByContract(_, _, let currency, let days):
            return .requestParameters([
                "vs_currency": currency.lowercased(),
                "days": days
            ], .urlEncoding)
        case .markets(let id, let currency):
            // `/coins/markets?ids=` is *not* case-sensitive, but it is
            // lower-cased anyway so the cache key and the request agree.
            return .requestParameters([
                "vs_currency": currency.lowercased(),
                "ids": id.lowercased(),
                "price_change_percentage": "1h,24h,7d,30d"
            ], .urlEncoding)
        }
    }
}
