import Foundation
import OSLog

/// A per-chain-family strategy that turns a set of token contract addresses into
/// USD (and per-currency) rates. Each blockchain family prices tokens from a
/// different source — an on-chain pool, a THORChain/MAYAChain pool, or the
/// CoinGecko/LiFi HTTP APIs — so `CryptoPriceService` resolves the right strategy
/// via `TokenPriceSourceRegistry` and persists whatever rates it returns.
protocol TokenPriceSource {
    func prices(contracts: [String], coins: [CoinMeta]) async throws -> [Rate]
}

/// Resolves the `TokenPriceSource` for a chain family. EVM and other CoinGecko
/// chains fall through to the CoinGecko-by-contract source with a LiFi fallback.
enum TokenPriceSourceRegistry {
    static func source(for chain: Chain, httpClient: HTTPClientProtocol = HTTPClient()) -> TokenPriceSource {
        switch chain {
        case .solana:
            return SolanaTokenPriceSource()
        case .sui:
            return SuiTokenPriceSource(httpClient: httpClient)
        case .mayaChain:
            return MayaChainTokenPriceSource(httpClient: httpClient)
        case .thorChain, .thorChainChainnet, .thorChainStagenet:
            return ThorChainTokenPriceSource(chain: chain)
        default:
            return CoinGeckoContractTokenPriceSource(chain: chain, httpClient: httpClient)
        }
    }
}

// MARK: - Solana

/// Prices Solana SPL tokens from their on-chain liquidity pool via `SolanaService`.
struct SolanaTokenPriceSource: TokenPriceSource {
    func prices(contracts: [String], coins: [CoinMeta]) async throws -> [Rate] {
        var rates: [Rate] = []
        for contract in contracts {
            let decimals = coins.first(where: {
                $0.chain == .solana && $0.contractAddress == contract
            })?.decimals ?? 6

            let poolPrice = await SolanaService.getTokenUSDValue(contractAddress: contract, decimals: decimals)
            let poolRate: Rate = .init(fiat: "usd", crypto: contract, value: poolPrice)
            rates.append(poolRate)
        }
        return rates
    }
}

// MARK: - Sui

/// Prices Sui tokens by coin type through CoinGecko, with the existing Cetus
/// liquidity route as a fallback for coin types CoinGecko does not resolve.
struct SuiTokenPriceSource: TokenPriceSource {
    typealias FallbackPrice = (String, Int) async -> Double
    typealias CurrencyConverter = (Double, SettingsCurrency) -> Double?

    let httpClient: HTTPClientProtocol
    let fallbackPrice: FallbackPrice
    let currencyConverter: CurrencyConverter
    private let logger = Log.chain.service

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        fallbackPrice: @escaping FallbackPrice = { contract, decimals in
            await SuiService.getTokenUSDValue(contractAddress: contract, decimals: decimals)
        },
        currencyConverter: @escaping CurrencyConverter = { usdPrice, currency in
            SuiTokenPriceSource.convertFallbackUSDPrice(usdPrice, to: currency)
        }
    ) {
        self.httpClient = httpClient
        self.fallbackPrice = fallbackPrice
        self.currencyConverter = currencyConverter
    }

    func prices(contracts: [String], coins: [CoinMeta]) async throws -> [Rate] {
        let currencies = SettingsCurrency.allCases
            .map(\.rawValue)
            .joined(separator: ",")
        let response: [String: [String: Double]]

        do {
            response = try await httpClient.request(
                CryptoPriceAPI.pricesByContract(
                    network: CoinGeckoPlatform.id(for: .sui),
                    addresses: contracts.joined(separator: ","),
                    currencies: currencies
                ),
                responseType: [String: [String: Double]].self
            ).data
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw error
            }
            logger.warning("CoinGecko Sui token price fetch failed: \(error.localizedDescription, privacy: .public)")
            response = [:]
        }

        var rates: [Rate] = []
        for contract in contracts {
            if let priceMap = response.first(where: {
                SuiCoinType.matches($0.key, contract)
            })?.value {
                let coinGeckoRates: [Rate] = SettingsCurrency.allCases.compactMap { currency in
                    let fiat = currency.rawValue.lowercased()
                    guard let value = priceMap[fiat], value.isFinite, value > 0 else { return nil }
                    return Rate(fiat: fiat, crypto: SuiCoinType.rateKey(contract), value: value)
                }
                if !coinGeckoRates.isEmpty {
                    rates.append(contentsOf: coinGeckoRates)
                    continue
                }
            }

            guard let tokenMeta = coins.first(where: {
                $0.chain == .sui &&
                    !$0.isNativeToken &&
                    SuiCoinType.matches($0.contractAddress, contract)
            }) else {
                logger.warning("No runtime metadata found for Sui token \(contract, privacy: .public), skipping fallback price fetch")
                continue
            }

            let poolPrice = await fallbackPrice(contract, tokenMeta.decimals)
            guard poolPrice.isFinite, poolPrice > 0 else {
                logger.warning("No positive fallback price found for Sui token \(contract, privacy: .public)")
                continue
            }
            rates.append(contentsOf: SettingsCurrency.allCases.compactMap { currency in
                guard let value = currencyConverter(poolPrice, currency), value.isFinite, value > 0 else {
                    return nil
                }
                return Rate(
                    fiat: currency.rawValue.lowercased(),
                    crypto: SuiCoinType.rateKey(contract),
                    value: value
                )
            })
        }
        return rates
    }

    /// Cetus returns USD only. Derive the requested currency through the cached
    /// native SUI cross-rate, which is refreshed from CoinGecko for every
    /// supported wallet currency alongside token prices.
    static func convertFallbackUSDPrice(_ usdPrice: Double, to currency: SettingsCurrency) -> Double? {
        guard currency != .USD else { return usdPrice }
        guard let suiUSD = RateProvider.shared.rate(for: TokensStore.Token.suiSUI, currency: .USD)?.value,
              let suiCurrency = RateProvider.shared.rate(for: TokensStore.Token.suiSUI, currency: currency)?.value,
              suiUSD.isFinite,
              suiCurrency.isFinite,
              suiUSD > 0,
              suiCurrency > 0 else {
            return nil
        }
        return usdPrice * suiCurrency / suiUSD
    }
}

// MARK: - MAYAChain

/// Prices MAYAChain pool assets by deriving their price in CACAO from the
/// mayanode pool depths and multiplying by the CACAO/USD rate. CACAO's own price
/// is pre-fetched (and persisted) when not already cached.
struct MayaChainTokenPriceSource: TokenPriceSource {
    let httpClient: HTTPClientProtocol
    private let logger = Log.chain.service

    func prices(contracts: [String], coins: [CoinMeta]) async throws -> [Rate] {
        if RateProvider.shared.rate(for: TokensStore.cacao) == nil {
            logger.info("CACAO price not cached, fetching before MAYAChain pool pricing")
            try? await CoinGeckoRates.fetchAndSaveByIds(
                [TokensStore.cacao.priceProviderId],
                httpClient: httpClient,
                logger: logger
            )
        }

        guard let cacaoRate = RateProvider.shared.rate(for: TokensStore.cacao) else {
            logger.warning("CACAO price unavailable, cannot derive MAYAChain pool prices")
            return []
        }

        let cacaoPriceUSD = cacaoRate.value

        var rates: [Rate] = []
        for contract in contracts {
            let assetName = "MAYA.\(contract.uppercased())"
            if let price = await poolPrice(assetName: assetName, cacaoPriceUSD: cacaoPriceUSD, coins: coins) {
                rates.append(Rate(fiat: "usd", crypto: contract, value: price))
            }
        }

        return rates
    }

    private func poolPrice(assetName: String, cacaoPriceUSD: Double, coins: [CoinMeta]) async -> Double? {
        do {
            let response = try await httpClient.request(
                CryptoPriceAPI.mayaChainPool(asset: assetName),
                responseType: MAYAChainPoolResponse.self
            )
            return Self.calculatePoolPrice(pool: response.data, cacaoPriceUSD: cacaoPriceUSD, coins: coins, assetName: assetName)
        } catch {
            logger.warning("Failed to fetch MAYAChain pool price for \(assetName): \(error.localizedDescription)")
            return nil
        }
    }

    /// Pure computation for the MAYAChain pool-derived USD price of a non-CACAO Maya asset.
    /// Static so unit tests can validate the math without exercising the live mayanode endpoint.
    static func calculatePoolPrice(pool: MAYAChainPoolResponse, cacaoPriceUSD: Double, coins: [CoinMeta], assetName: String) -> Double {
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

// MARK: - THORChain

/// Prices THORChain assets from THORChain pools, with special-casing for the
/// yield tokens (yRUNE / yTCY / ybRUNE) and sanitisation of `x/` and `STAKING-`
/// prefixes before the pool lookup.
///
/// A pool lookup only answers for an asset that actually has an L1 pool.
/// THORChain *derived* assets have none — `/thorchain/pool/THOR.BRUNE` replies
/// `"asset: THOR.BRUNE is a derived asset"` and `getAssetPriceInUSD` reports
/// `0.0` — so when the pool has no price this falls back to the CoinGecko feed
/// the token's curated `TokensStore` entry declares via `priceProviderId`.
/// bRUNE names RUNE's own feed, which is what prices it at RUNE parity, the
/// same result vultisig-android reaches by pricing every `priceProviderID`
/// -bearing token from CoinGecko and never asking the pool. The pool stays
/// first so every asset that does have one (TCY, RUJI and their staking
/// receipts) keeps pricing exactly as it does today.
///
/// This path is only reached for a coin whose stored `priceProviderId` is
/// empty: `RateProvider.cryptoId(for:)` routes a coin that carries one to the
/// provider-id price fetch instead. A coin auto-discovered before its curated
/// entry existed was persisted without one and is never re-synced, which is how
/// a held bRUNE ends up priced from a pool that cannot exist.
struct ThorChainTokenPriceSource: TokenPriceSource {
    /// NAV-derived USD price for a yield token's contract denom.
    typealias YieldPrice = (Chain, String) async -> Double?
    /// USD price for a fully qualified THORChain pool asset (e.g. `THOR.TCY`).
    typealias PoolPrice = (Chain, String) async -> Double
    /// Cached USD rate for a curated token's declared CoinGecko feed.
    typealias ProviderRate = (CoinMeta) -> Double?
    /// Fetches and persists one CoinGecko provider id's rates.
    typealias ProviderFeedFetch = (String) async -> Void

    let chain: Chain
    private let yieldPrice: YieldPrice
    private let poolPrice: PoolPrice
    private let providerRate: ProviderRate
    private let fetchProviderFeed: ProviderFeedFetch
    private let logger = Log.chain.service

    init(
        chain: Chain,
        yieldPrice: @escaping YieldPrice = { chain, contract in
            await ThorchainServiceFactory.getService(for: chain).fetchYieldTokenPrice(for: contract)
        },
        poolPrice: @escaping PoolPrice = { chain, assetName in
            await ThorchainServiceFactory.getService(for: chain).getAssetPriceInUSD(assetName: assetName)
        },
        providerRate: @escaping ProviderRate = { coin in
            RateProvider.shared.rate(for: coin, currency: .USD)?.value
        },
        fetchProviderFeed: @escaping ProviderFeedFetch = { providerId in
            _ = try? await CoinGeckoRates.fetchAndSaveByIds(
                [providerId],
                httpClient: HTTPClient(),
                logger: Log.chain.service
            )
        }
    ) {
        self.chain = chain
        self.yieldPrice = yieldPrice
        self.poolPrice = poolPrice
        self.providerRate = providerRate
        self.fetchProviderFeed = fetchProviderFeed
    }

    func prices(contracts: [String], coins _: [CoinMeta]) async throws -> [Rate] {
        let yieldTokens = TokensStore.TokenSelectionAssets
            .filter { $0.chain == chain && ($0.ticker == "yRUNE" || $0.ticker == "yTCY" || $0.ticker == "ybRUNE") }
            .map { $0.contractAddress }

        // Two contracts can name the same declared feed (a stale TCY and sTCY both
        // name `tcy`), so remember which feeds this batch already tried to fetch
        // and don't issue the same request twice. A later refresh retries.
        var attemptedFeeds: Set<String> = []
        var rates: [Rate] = []
        for contract in contracts {
            if yieldTokens.contains(contract) {
                let price = await yieldPrice(chain, contract)
                rates.append(Rate(fiat: "usd", crypto: contract, value: price ?? 0.0))
                continue
            }

            let poolPriceUSD = await poolPrice(chain, Self.poolAssetName(for: contract))
            if poolPriceUSD.isFinite, poolPriceUSD > 0 {
                rates.append(Rate(fiat: "usd", crypto: contract, value: poolPriceUSD))
                continue
            }

            if let declaredRate = await declaredFeedRate(for: contract, attemptedFeeds: &attemptedFeeds) {
                rates.append(declaredRate)
            } else {
                // No pool and no declared feed to fall back on: keep reporting the
                // pool's zero so the caller's behaviour is unchanged for assets
                // that have never had a price (e.g. LQDY, whose pool doesn't exist).
                rates.append(Rate(fiat: "usd", crypto: contract, value: poolPriceUSD))
            }
        }
        return rates
    }

    /// The pool asset a THORChain token denom is priced from: `x/` and a leading
    /// `STAKING-` are stripped (a staking receipt prices off its underlying
    /// asset's pool) and a bare symbol is qualified with the `THOR.` prefix.
    static func poolAssetName(for contract: String) -> String {
        var sanitisedContract = contract.uppercased().replacingOccurrences(of: "X/", with: "")

        // Handle staking assets mappings to their underlying asset for price
        if sanitisedContract.starts(with: "STAKING-") {
            sanitisedContract = sanitisedContract.replacingOccurrences(of: "STAKING-", with: "")
        }

        // Ensure we have the THOR. prefix for the pool lookup
        return sanitisedContract.contains(".") ? sanitisedContract : "THOR.\(sanitisedContract)"
    }

    /// The USD rate for `contract` read off the CoinGecko feed its curated
    /// `TokensStore` entry declares. `nil` when the token isn't curated, declares
    /// no feed, or that feed can't be resolved at all.
    ///
    /// The feed is usually already cached: `CryptoPriceService` resolves
    /// provider-id prices before contract prices, and any vault holding bRUNE also
    /// holds native RUNE, which names the same feed. A *single-coin* refresh
    /// (`BalanceService.updateBalance(for:)`, behind a coin-detail screen) carries
    /// no such coin, so on a cold cache the feed is fetched here first — the same
    /// pre-fetch `MayaChainTokenPriceSource` performs for CACAO.
    ///
    /// USD only, matching the pool price it stands in for. Emitting the feed's
    /// other currencies would leave them stranded the moment an asset went back to
    /// pool pricing, since the pool path has no per-currency rates to refresh them
    /// with — the wider non-USD gap in every contract-keyed price source is its own
    /// problem, not this one's.
    private func declaredFeedRate(for contract: String, attemptedFeeds: inout Set<String>) async -> Rate? {
        guard let curated = TokensStore.findTokenMeta(chain: chain, contractAddress: contract),
              !curated.priceProviderId.isEmpty else {
            return nil
        }

        var feedRate = providerRate(curated)
        if feedRate == nil, attemptedFeeds.insert(curated.priceProviderId).inserted {
            await fetchProviderFeed(curated.priceProviderId)
            feedRate = providerRate(curated)
        }

        guard let value = feedRate, value.isFinite, value > 0 else {
            logger.warning("No \(curated.priceProviderId, privacy: .public) rate to price \(curated.ticker, privacy: .public) from")
            return nil
        }

        return Rate(fiat: "usd", crypto: contract, value: value)
    }
}

// MARK: - CoinGecko + LiFi (default)

/// Prices tokens via CoinGecko's token-price-by-contract endpoint, falling back
/// to LiFi for contracts CoinGecko does not resolve. Used for EVM chains and any
/// chain without a dedicated pool-based source.
struct CoinGeckoContractTokenPriceSource: TokenPriceSource {
    let chain: Chain
    let httpClient: HTTPClientProtocol
    private let logger = Log.chain.service

    func prices(contracts: [String], coins _: [CoinMeta]) async throws -> [Rate] {
        let currencies = SettingsCurrency.allCases
            .map { $0.rawValue }
            .joined(separator: ",")

        let addresses = contracts.joined(separator: ",")
        let response = try await httpClient.request(
            CryptoPriceAPI.pricesByContract(
                network: CoinGeckoPlatform.id(for: chain),
                addresses: addresses,
                currencies: currencies
            ),
            responseType: [String: [String: Double]].self
        ).data

        let contractsNotFoundOnCoingecko = contracts.filter { !response.keys.contains($0) }

        var rates = CoinGeckoRates.map(response: response)

        // now lets try to find the price for the notFoundPricesOnCoingecko
        for contract in contractsNotFoundOnCoingecko {
            if let lifiRate = try await fetchLifiTokenPrice(contract: contract) {
                rates.append(lifiRate)
            }
        }

        return rates
    }

    private func fetchLifiTokenPrice(contract: String) async throws -> Rate? {
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
}

// MARK: - CoinGecko platform mapping

/// CoinGecko `asset_platforms` id per chain. Any chain absent from the table maps
/// to `.empty`.
enum CoinGeckoPlatform {
    static let byChain: [Chain: String] = [
        .ethereum: "ethereum",
        .ethereumSepolia: "ethereum",
        .avalanche: "avalanche",
        .base: "base",
        .blast: "blast",
        .arbitrum: "arbitrum-one",
        .polygon: "polygon-pos",
        .polygonV2: "polygon-pos",
        .optimism: "optimistic-ethereum",
        .bscChain: "binance-smart-chain",
        .zksync: "zksync",
        .mantle: "mantle",
        .cronosChain: "cronos",
        .hyperliquid: "hyperliquid",
        .sei: "sei-network",
        .sui: "sui",
        .robinhood: "robinhood"
    ]

    static func id(for chain: Chain) -> String {
        byChain[chain] ?? .empty
    }
}

// MARK: - Shared CoinGecko rate helpers

/// Shared helpers for the CoinGecko simple-price / token-price responses, reused by
/// the provider-id price path and the MAYAChain CACAO pre-fetch.
enum CoinGeckoRates {
    /// Maps a CoinGecko response (`{ crypto: { fiat: value } }`) into per-currency `Rate`s.
    static func map(response: [String: [String: Double]]) -> [Rate] {
        let rates: [[Rate]] = response.map { crypto, map in
            return SettingsCurrency.allCases.compactMap { currency in
                let fiat = currency.rawValue.lowercased()
                guard let value = map[fiat] else { return nil }
                return Rate(fiat: fiat, crypto: crypto, value: value)
            }
        }

        return Array(rates.joined())
    }

    /// Fetches CoinGecko simple-price rates for the given provider ids and persists them.
    static func fetchAndSaveByIds(_ ids: [String], httpClient: HTTPClientProtocol, logger: Logger) async throws {
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
            try await RateProvider.shared.save(rates: map(response: response.data))
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled {
                logger.debug("Price fetch cancelled")
            }
            throw error
        }
    }
}
