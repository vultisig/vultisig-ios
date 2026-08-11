//
//  LimitSwapDraft.swift
//  VultisigApp
//

import BigInt
import Foundation

/// User-editable limit-swap form state. Pure value type so tests, snapshot
/// comparisons, and SwiftUI `@Bindable` projections all work without
/// reference-identity surprises.
struct LimitSwapDraft: Equatable {
    var fromAsset: LimitSwapAsset
    var toAsset: LimitSwapAsset
    var sourceAmount: BigInt
    var targetPrice: Decimal
    /// Order lifetime in THORChain blocks — the unit the `=<` memo encodes and
    /// the unit `LimitOrder` persists, so the form holds no second representation
    /// that could drift from it. The duration picker converts minutes at its edge.
    var expiryBlocks: Int
    var displayUnit: PriceDisplayUnit
    var isFastVault: Bool
    var fastVaultPassword: String

    init(
        fromAsset: LimitSwapAsset,
        toAsset: LimitSwapAsset,
        sourceAmount: BigInt = 0,
        targetPrice: Decimal = 0,
        expiryBlocks: Int = THORChainConstants.blocks(forHours: 24),
        displayUnit: PriceDisplayUnit = .asset,
        isFastVault: Bool = false,
        fastVaultPassword: String = ""
    ) {
        self.fromAsset = fromAsset
        self.toAsset = toAsset
        self.sourceAmount = sourceAmount
        self.targetPrice = targetPrice
        self.expiryBlocks = expiryBlocks
        self.displayUnit = displayUnit
        self.isFastVault = isFastVault
        self.fastVaultPassword = fastVaultPassword
    }
}

/// Asset metadata extracted from a `Coin`. Lightweight value type so the draft
/// (and its tests) don't carry SwiftData `@Model` dependencies.
struct LimitSwapAsset: Equatable {
    let chain: Chain
    let ticker: String
    let decimals: Int
    let contractAddress: String
    let isNativeToken: Bool
    /// Coin logo identifier — pass to `AsyncImageView`'s `logo:` parameter.
    /// Empty string for tests / placeholder assets where the picker hasn't run.
    let logo: String
    /// Chain logo identifier — pass to `AsyncImageView`'s `tokenChainLogo:`
    /// parameter. Empty string when not available.
    let chainLogo: String
    /// CoinGecko id, carried so the asset can be priced.
    ///
    /// Without it an asset cannot be resolved to a market-data source at all:
    /// the lookup falls back to the contract address, which is empty for every
    /// native asset — so BTC, ETH and RUNE, the assets limit orders are mostly
    /// written against, would silently have no price history. Defaulted only
    /// for fixtures; the production path is `init(coin:)`, which always carries
    /// the real id.
    let priceProviderId: String

    init(
        chain: Chain,
        ticker: String,
        decimals: Int,
        contractAddress: String,
        isNativeToken: Bool,
        logo: String = "",
        chainLogo: String = "",
        priceProviderId: String = ""
    ) {
        self.chain = chain
        self.ticker = ticker
        self.decimals = decimals
        self.contractAddress = contractAddress
        self.isNativeToken = isNativeToken
        self.logo = logo
        self.chainLogo = chainLogo
        self.priceProviderId = priceProviderId
    }

    /// The asset as the shared market-data layer expects it.
    ///
    /// `MarketDataService` routes on `RateProvider.cryptoId(for:)`, which reads
    /// the price-provider id first and the contract address second, so this is
    /// only meaningful because the id is carried above.
    var coinMeta: CoinMeta {
        CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: logo,
            decimals: decimals,
            priceProviderId: priceProviderId,
            contractAddress: contractAddress,
            isNativeToken: isNativeToken
        )
    }

    /// THORChain memo asset string form, e.g. `BTC.BTC` or `ETH.USDC-EC7`.
    /// `nil` if the chain isn't currently routable through THORChain.
    var memoSymbol: String? {
        thorchainMemoAsset(
            chain: chain,
            ticker: ticker,
            contractAddress: contractAddress,
            isNativeToken: isNativeToken
        )
    }

    /// The same asset spelled the way a CANCEL memo must spell it — full
    /// contract address for EVM tokens. Captured at signing because
    /// `memoSymbol`'s 6-character abbreviation cannot be reversed afterwards.
    var cancelMemoSymbol: String? {
        thorchainCancelMemoAsset(
            chain: chain,
            ticker: ticker,
            contractAddress: contractAddress,
            isNativeToken: isNativeToken
        )
    }
}

extension LimitSwapAsset {
    init(coin: Coin) {
        self.init(
            chain: coin.chain,
            ticker: coin.ticker,
            decimals: coin.decimals,
            contractAddress: coin.contractAddress,
            isNativeToken: coin.isNativeToken,
            logo: coin.logo,
            chainLogo: coin.tokenChainLogo ?? "",
            priceProviderId: coin.priceProviderId
        )
    }
}

enum PriceDisplayUnit: Equatable {
    case usd
    case asset
}
