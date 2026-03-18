//
//  MayaPoolStats.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 25/11/2025.
//

import Foundation

/// Response from /v2/pools with detailed statistics
struct MayaPoolStats: Codable {
    let asset: String
    let assetDepth: String
    let runeDepth: String
    let liquidityUnits: String
    let annualPercentageRate: String
    let poolAPY: String
    let assetPrice: String
    let assetPriceUSD: String
    let status: String
    let synthUnits: String?
    let synthSupply: String?
    let earningsAnnualAsPercentOfDepth: String?
    let lpLuvi: String?
    let saversAPR: String?
    let units: String

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

    var aprDecimal: Double {
        Double(annualPercentageRate) ?? 0.0
    }

    var aprPercentage: Double {
        aprDecimal * 100
    }

    var apyDecimal: Double {
        Double(poolAPY) ?? 0.0
    }

    var apyPercentage: Double {
        apyDecimal * 100
    }

    var earningsBasedAPRDecimal: Double {
        guard let earningsAPR = earningsAnnualAsPercentOfDepth else { return aprDecimal }
        return Double(earningsAPR) ?? aprDecimal
    }

    var earningsBasedAPRPercentage: Double {
        earningsBasedAPRDecimal * 100
    }

    var saversAPRDecimal: Double {
        guard let savers = saversAPR else { return 0.0 }
        return Double(savers) ?? 0.0
    }

    var saversAPRPercentage: Double {
        saversAPRDecimal * 100
    }

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
