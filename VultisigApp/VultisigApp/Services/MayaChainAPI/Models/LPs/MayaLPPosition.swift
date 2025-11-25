//
//  MayaLPPosition.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 25/11/2025.
//

import Foundation

/// Represents a complete LP position with calculated current values for MayaChain
struct MayaLPPosition {
    let runeRedeemValue: String
    let assetRedeemValue: String
    let poolStats: MayaPoolStats

    /// Pool asset identifier (e.g., "BTC.BTC")
    var asset: String {
        poolStats.asset
    }

    /// Current CACAO amount in the position (using redeem value from API)
    var currentRuneAmount: Decimal {
        Decimal(string: runeRedeemValue) ?? 0
    }

    /// Current asset amount in the position (using redeem value from API)
    var currentAssetAmount: Decimal {
        Decimal(string: assetRedeemValue) ?? 0
    }

    /// Annual Percentage Rate as decimal (e.g., 0.0067 for 0.67%)
    var apr: Double {
        return poolStats.aprDecimal
    }
}
