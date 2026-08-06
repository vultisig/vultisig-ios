//
//  MarketDataService.swift
//  VultisigApp
//
//  Price history + market snapshot for the coin-detail screen. Routes a coin to
//  a CoinGecko id or an asset-platform contract using the same rule
//  `CryptoPriceService` uses for spot prices, and caches per
//  (source, range, currency) through the shared `TTLCache`.
//

import Foundation

/// Which CoinGecko route a coin's market data comes from.
///
/// Mirrors `RateProvider.CryptoId`, but resolved one step further: the contract
/// case also carries the CoinGecko asset-platform slug, which the chart path
/// needs and the spot-price path already looks up separately.
enum MarketDataSource: Hashable, Sendable {
    case id(String)
    case contract(platform: String, address: String)
}

protocol MarketDataServiceProtocol: Sendable {
    /// Price series for `coin` over `range`, or `nil` when the coin has no
    /// CoinGecko source, the series is too sparse to draw, or the fetch failed
    /// with nothing cached to fall back on.
    func chart(
        for coin: CoinMeta,
        range: MarketChartRange,
        currency: SettingsCurrency
    ) async -> MarketChart?

    /// Market snapshot for `coin`, or `nil` when the coin has no CoinGecko id
    /// or the fetch failed with nothing cached.
    func stats(for coin: CoinMeta, currency: SettingsCurrency) async -> CoinMarketStats?
}

final class MarketDataService: MarketDataServiceProtocol {

    static let shared = MarketDataService()

    private struct ChartKey: Hashable {
        let source: MarketDataSource
        let range: MarketChartRange
        let currency: String
    }

    private struct StatsKey: Hashable {
        let id: String
        let currency: String
    }

    /// How long a market snapshot stays fresh. Matches the shortest chart
    /// range: both are "what the price is doing right now" reads.
    private static let statsCacheTTL: TimeInterval = 60

    private let httpClient: HTTPClientProtocol
    private let chartCache = TTLCache<ChartKey, MarketChart>()
    private let statsCache = TTLCache<StatsKey, CoinMarketStats>()
    private let now: @Sendable () -> Date
    private let logger = Log.wallet.service

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.httpClient = httpClient
        self.now = now
    }

    // MARK: - Routing

    /// The CoinGecko route for `coin`, or `nil` when it has none.
    ///
    /// Follows `CryptoPriceService.resolveSources` so a coin that gets a spot
    /// price from an id also gets its chart from that id. Pool-priced assets
    /// (Solana/Sui pool, THOR/Maya pool) resolve to a contract on a chain with
    /// no CoinGecko asset platform, and fall out here as unsupported.
    /// Ids and addresses are lower-cased here, not just when the path is built,
    /// so two spellings of the same coin share one cache entry instead of
    /// fetching the same series twice.
    static func resolveSource(for coin: CoinMeta) -> MarketDataSource? {
        switch RateProvider.cryptoId(for: coin) {
        case .priceProvider(let id):
            guard !id.isEmpty else { return nil }
            return .id(id.lowercased())
        case .contract(let address):
            let platform = CoinGeckoPlatform.id(for: coin.chain)
            let requestAddress = coin.chain == .sui
                ? SuiCoinType.normalize(coin.contractAddress)
                : address.lowercased()
            guard !platform.isEmpty, !requestAddress.isEmpty else { return nil }
            return .contract(platform: platform.lowercased(), address: requestAddress)
        }
    }

    // MARK: - Chart

    func chart(
        for coin: CoinMeta,
        range: MarketChartRange,
        currency: SettingsCurrency
    ) async -> MarketChart? {
        guard let source = Self.resolveSource(for: coin) else { return nil }

        let key = ChartKey(source: source, range: range, currency: currency.rawValue)
        let target = Self.chartTarget(source: source, range: range, currency: currency)

        do {
            let chart = try await chartCache.value(
                for: key,
                now: now(),
                ttl: range.cacheTTL
            ) { [httpClient] in
                try await httpClient.request(target, responseType: MarketChart.self).data
            }
            // Resampled only after the usability floor: the floor counts real
            // samples, and interpolating first would turn a two-point series
            // into a plausible-looking two-hundred-point line.
            return chart.isUsable ? chart.resampled() : nil
        } catch is CancellationError {
            // The caller is tearing this load down — switching range, or
            // closing the sheet. Serving a stale series here would undo the
            // cancel rather than honour it.
            return nil
        } catch {
            logger.warning("Market chart unavailable for \(coin.ticker, privacy: .public): \(error.localizedDescription, privacy: .public)")
            guard let cached = await chartCache.peek(key), cached.isUsable else { return nil }
            return cached.resampled()
        }
    }

    private static func chartTarget(
        source: MarketDataSource,
        range: MarketChartRange,
        currency: SettingsCurrency
    ) -> MarketDataAPI {
        switch source {
        case .id(let id):
            return .marketChartById(id: id, currency: currency.rawValue, days: range.days)
        case .contract(let platform, let address):
            return .marketChartByContract(
                platform: platform,
                contract: address,
                currency: currency.rawValue,
                days: range.days
            )
        }
    }

    // MARK: - Stats

    func stats(for coin: CoinMeta, currency: SettingsCurrency) async -> CoinMarketStats? {
        // `/coins/markets` is keyed by id only — there is no contract variant —
        // so a token that charts by contract has no market snapshot. It renders
        // its chart without the stats sections rather than showing empty rows.
        guard case .id(let id)? = Self.resolveSource(for: coin) else { return nil }

        let key = StatsKey(id: id.lowercased(), currency: currency.rawValue)

        do {
            return try await statsCache.value(
                for: key,
                now: now(),
                ttl: Self.statsCacheTTL
            ) { [httpClient] in
                let records = try await httpClient.request(
                    MarketDataAPI.markets(id: id, currency: currency.rawValue),
                    responseType: [CoinMarketStats].self
                ).data

                guard let record = records.first else {
                    throw MarketDataError.noRecord(id: id)
                }
                return record
            }
        } catch is CancellationError {
            return nil
        } catch {
            logger.warning("Market stats unavailable for \(coin.ticker, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return await statsCache.peek(key)
        }
    }
}

enum MarketDataError: Error, LocalizedError {
    /// `/coins/markets` answered `200` with an empty array — the id is not one
    /// CoinGecko knows. Thrown rather than returned so `TTLCache` does not
    /// store the miss as a good snapshot.
    case noRecord(id: String)

    var errorDescription: String? {
        switch self {
        case .noRecord(let id):
            return "No CoinGecko market record for \(id)"
        }
    }
}
