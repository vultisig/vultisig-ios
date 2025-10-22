//
//  THORChainPoolStats.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation

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
