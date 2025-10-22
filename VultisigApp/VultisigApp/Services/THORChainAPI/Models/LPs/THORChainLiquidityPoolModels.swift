//
//  THORChainLiquidityPoolModels.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation

// MARK: - Liquidity Provider Details Response

/// Response from /thorchain/pool/{asset-id}/liquidity_provider/{wallet-address}
struct THORChainLiquidityProviderResponse: Codable {
    let asset: String
    let runeAddress: String
    let assetAddress: String
    let lastAddHeight: Int64
    let units: String
    let pendingRune: String
    let pendingAsset: String
    let pendingTxId: String?
    let runeDepositValue: String
    let assetDepositValue: String
    let runeRedeemValue: String
    let assetRedeemValue: String
    let luviDepositValue: String
    let luviRedeemValue: String
    let luviGrowthPct: String

    enum CodingKeys: String, CodingKey {
        case asset
        case runeAddress = "rune_address"
        case assetAddress = "asset_address"
        case lastAddHeight = "last_add_height"
        case units
        case pendingRune = "pending_rune"
        case pendingAsset = "pending_asset"
        case pendingTxId = "pending_tx_id"
        case runeDepositValue = "rune_deposit_value"
        case assetDepositValue = "asset_deposit_value"
        case runeRedeemValue = "rune_redeem_value"
        case assetRedeemValue = "asset_redeem_value"
        case luviDepositValue = "luvi_deposit_value"
        case luviRedeemValue = "luvi_redeem_value"
        case luviGrowthPct = "luvi_growth_pct"
    }

    /// Current RUNE amount (redeemable value)
    var runeRedeemValueBigInt: UInt64 {
        UInt64(runeRedeemValue) ?? 0
    }

    /// Current asset amount (redeemable value)
    var assetRedeemValueBigInt: UInt64 {
        UInt64(assetRedeemValue) ?? 0
    }

    /// Liquidity units
    var unitsBigInt: UInt64 {
        UInt64(units) ?? 0
    }

    /// LUVI growth as percentage
    var luviGrowthPercentage: Double {
        Double(luviGrowthPct) ?? 0.0
    }
}

// MARK: - Depth History Response

/// Response from /v2/history/depths/{asset}
struct THORChainDepthHistory: Codable {
    struct Meta: Codable {
        let luviIncrease: String?
    }

    struct Interval: Codable {
        let luvi: String?
        let startTime: String?
        let endTime: String?
    }

    let meta: Meta
    let intervals: [Interval]

    /// Calculate manual APR from LUVI history
    /// - Parameter days: Number of days in the period
    /// - Returns: APR as decimal (e.g., 0.2433 for 24.33%)
    func calculateAPR(days: Int) -> Decimal {
        // First, try to use luviIncrease from meta if available
        if let luviIncreaseStr = meta.luviIncrease,
           let luviIncrease = Decimal(string: luviIncreaseStr) {
            // APR = growth * (365 / days)
            return luviIncrease * Decimal(365) / Decimal(days)
        }

        // Otherwise, calculate from first and last interval LUVI
        guard
            let firstLuviStr = intervals.first?.luvi,
            let lastLuviStr = intervals.last?.luvi,
            let firstLuvi = Decimal(string: firstLuviStr),
            let lastLuvi = Decimal(string: lastLuviStr),
            firstLuvi > 0
        else {
            return 0
        }

        // Calculate growth: (lastLUVI / firstLUVI) - 1
        let growth = (lastLuvi / firstLuvi) - 1

        // Annualize: APR = growth * (365 / days)
        return growth * Decimal(365) / Decimal(days)
    }
}

// MARK: - Pool Stats Response

/// Response from /v2/pools with detailed statistics
/// Note: APR values are LUVI-based (Liquidity Unit Value Index growth)
/// calculated over the specified period (default 30d, configurable via period parameter)
struct THORChainPoolStats: Codable {
    let asset: String
    let assetDepth: String
    let runeDepth: String
    let liquidityUnits: String
    let annualPercentageRate: String  // LUVI-based APR (decimal format, e.g., "0.0067" = 0.67%)
    let poolAPY: String
    let assetPrice: String
    let assetPriceUSD: String
    let status: String
    let synthUnits: String?
    let synthSupply: String?
    let earningsAnnualAsPercentOfDepth: String?  // Alternative earnings-based APR
    let lpLuvi: String?  // LP LUVI value (may be "NaN" for some pools)
    let saversAPR: String?  // Savers APR (if applicable)

    /// Convenience computed properties
    var assetDepthBigInt: UInt64 {
        UInt64(assetDepth) ?? 0
    }

    var runeDepthBigInt: UInt64 {
        UInt64(runeDepth) ?? 0
    }

    var liquidityUnitsBigInt: UInt64 {
        UInt64(liquidityUnits) ?? 0
    }

    /// LUVI-based APR as decimal (e.g., 0.0067 for 0.67%)
    /// This is calculated from liquidity unit value growth over the period
    var aprDecimal: Double {
        Double(annualPercentageRate) ?? 0.0
    }

    /// LUVI-based APR as percentage (e.g., 0.67 for 0.67%)
    var aprPercentage: Double {
        aprDecimal * 100
    }

    /// APY as decimal (accounts for compounding)
    var apyDecimal: Double {
        Double(poolAPY) ?? 0.0
    }

    /// APY as percentage
    var apyPercentage: Double {
        apyDecimal * 100
    }

    /// Alternative earnings-based APR
    var earningsBasedAPRDecimal: Double {
        guard let earningsAPR = earningsAnnualAsPercentOfDepth else { return aprDecimal }
        return Double(earningsAPR) ?? aprDecimal
    }

    /// Alternative earnings-based APR as percentage
    var earningsBasedAPRPercentage: Double {
        earningsBasedAPRDecimal * 100
    }

    /// Savers APR as decimal (e.g., 0.0875 for 8.75%)
    var saversAPRDecimal: Double {
        guard let savers = saversAPR else { return 0.0 }
        return Double(savers) ?? 0.0
    }

    /// Savers APR as percentage (e.g., 8.75 for 8.75%)
    var saversAPRPercentage: Double {
        saversAPRDecimal * 100
    }

    /// LP LUVI value as Decimal
    var lpLuviDecimal: Decimal {
        guard let luvi = lpLuvi, luvi.lowercased() != "nan" else { return 0 }
        return Decimal(string: luvi) ?? 0
    }

    var assetPriceDouble: Decimal {
        assetPrice.toDecimal()
    }

    var assetPriceUSDDouble: Decimal {
        assetPriceUSD.toDecimal()
    }

    var isAvailable: Bool {
        status.lowercased() == "available"
    }
}

// MARK: - Combined LP Position

/// Represents a complete LP position with calculated current values
struct THORChainLPPosition {
    let liquidityProvider: THORChainLiquidityProviderResponse
    let poolStats: THORChainPoolStats
    let manualAPR: Decimal? // Manual APR calculated from LUVI history

    /// Pool asset identifier (e.g., "BTC.BTC")
    var asset: String {
        poolStats.asset
    }

    /// Current RUNE amount in the position (using redeem value from API)
    var currentRuneAmount: Decimal {
        Decimal(liquidityProvider.runeRedeemValueBigInt)
    }

    /// Current asset amount in the position (using redeem value from API)
    var currentAssetAmount: Decimal {
        Decimal(liquidityProvider.assetRedeemValueBigInt)
    }
    
    /// LUVI-based Annual Percentage Rate as decimal (e.g., 0.0067 for 0.67%)
    /// This represents the annualized growth of liquidity unit value over the period
    /// Formula: APR = ((LUVI_end / LUVI_start) - 1) * (365 / period_days)
    /// Use this for display with .formatted(.percent)
    /// Prefers manual APR from LUVI history if available, falls back to pool stats APR
    var apr: Double {
        if let manual = manualAPR {
            return Double(truncating: manual as NSDecimalNumber)
        }
        return poolStats.aprDecimal
    }
}
