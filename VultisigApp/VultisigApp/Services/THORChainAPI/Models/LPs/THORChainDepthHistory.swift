//
//  THORChainDepthHistory.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/10/2025.
//

import Foundation

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
