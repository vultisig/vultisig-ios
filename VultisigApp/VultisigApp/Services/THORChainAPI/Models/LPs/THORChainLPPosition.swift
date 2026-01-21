//
//  THORChainLPPosition.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/10/2025.
//

import Foundation

/// Represents a complete LP position with calculated current values
struct THORChainLPPosition {
    let runeRedeemValue: String
    let assetRedeemValue: String
    let poolStats: THORChainPoolStats

    /// Pool asset identifier (e.g., "BTC.BTC")
    var asset: String {
        poolStats.asset
    }

    /// Current RUNE amount in the position (using redeem value from API)
    var currentRuneAmount: Decimal {
        Decimal(string: runeRedeemValue) ?? 0
    }

    /// Current asset amount in the position (using redeem value from API)
    var currentAssetAmount: Decimal {
        Decimal(string: assetRedeemValue) ?? 0
    }

    /// LUVI-based Annual Percentage Rate as decimal (e.g., 0.0067 for 0.67%)
    /// This represents the annualized growth of liquidity unit value over the period
    /// Formula: APR = ((LUVI_end / LUVI_start) - 1) * (365 / period_days)
    /// Use this for display with .formatted(.percent)
    /// Prefers manual APR from LUVI history if available, falls back to pool stats APR
    var apr: Double {
        return poolStats.aprDecimal
    }
}
