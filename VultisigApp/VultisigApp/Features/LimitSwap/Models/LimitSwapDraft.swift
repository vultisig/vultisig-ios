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
    var expiryHours: Int
    var displayUnit: PriceDisplayUnit
    var isFastVault: Bool
    var fastVaultPassword: String

    init(
        fromAsset: LimitSwapAsset,
        toAsset: LimitSwapAsset,
        sourceAmount: BigInt = 0,
        targetPrice: Decimal = 0,
        expiryHours: Int = 24,
        displayUnit: PriceDisplayUnit = .asset,
        isFastVault: Bool = false,
        fastVaultPassword: String = ""
    ) {
        self.fromAsset = fromAsset
        self.toAsset = toAsset
        self.sourceAmount = sourceAmount
        self.targetPrice = targetPrice
        self.expiryHours = expiryHours
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
}

extension LimitSwapAsset {
    init(coin: Coin) {
        self.init(
            chain: coin.chain,
            ticker: coin.ticker,
            decimals: coin.decimals,
            contractAddress: coin.contractAddress,
            isNativeToken: coin.isNativeToken
        )
    }
}

enum PriceDisplayUnit: Equatable {
    case usd
    case asset
}
