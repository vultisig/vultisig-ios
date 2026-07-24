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
            return SuiTokenPriceSource()
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

/// Prices Sui tokens from their on-chain liquidity pool via `SuiService`. Tokens
/// without `TokensStore` metadata are skipped rather than priced with default
/// decimals.
struct SuiTokenPriceSource: TokenPriceSource {
    private let logger = Logger(subsystem: "com.vultisig.app", category: "crypto-price-service")

    func prices(contracts: [String], coins _: [CoinMeta]) async throws -> [Rate] {
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
        return rates
    }
}

// MARK: - MAYAChain

/// Prices MAYAChain pool assets by deriving their price in CACAO from the
/// mayanode pool depths and multiplying by the CACAO/USD rate. CACAO's own price
/// is pre-fetched (and persisted) when not already cached.
struct MayaChainTokenPriceSource: TokenPriceSource {
    let httpClient: HTTPClientProtocol
    private let logger = Logger(subsystem: "com.vultisig.app", category: "crypto-price-service")

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
struct ThorChainTokenPriceSource: TokenPriceSource {
    let chain: Chain

    func prices(contracts: [String], coins _: [CoinMeta]) async throws -> [Rate] {
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
        return rates
    }
}

// MARK: - CoinGecko + LiFi (default)

/// Prices tokens via CoinGecko's token-price-by-contract endpoint, falling back
/// to LiFi for contracts CoinGecko does not resolve. Used for EVM chains and any
/// chain without a dedicated pool-based source.
struct CoinGeckoContractTokenPriceSource: TokenPriceSource {
    let chain: Chain
    let httpClient: HTTPClientProtocol
    private let logger = Logger(subsystem: "com.vultisig.app", category: "crypto-price-service")

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

/// CoinGecko `asset_platforms` id per chain. Only EVM chains have a contract-based
/// CoinGecko platform; any chain absent from the table maps to `.empty`.
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
        .mantle: "mantle"
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
