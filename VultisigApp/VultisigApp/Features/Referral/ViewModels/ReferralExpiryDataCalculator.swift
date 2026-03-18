//
//  ReferralExpiryDataCalculator.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/08/2025.
//

import Foundation

enum ReferralExpiryDataCalculator {
    static let blocksPerSecond: UInt64 = 6
    static let blocksPerDay: UInt64 = (60 / blocksPerSecond) * 60 * 24
    static let blockPerYear: UInt64 = blocksPerDay * 365

    static func getFormattedExpiryDate(expiryBlock: UInt64, currentBlock: UInt64, extendedByYears: Int = 0) -> String {
        let date = calculateExpiryDate(expiryBlock: expiryBlock, currentBlock: currentBlock, extendedByYears: extendedByYears)
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy"
        formatter.locale = Locale(identifier: "en_US")

        return formatter.string(from: date)
    }

    static func calculateExpiryDate(expiryBlock: UInt64, currentBlock: UInt64, extendedByYears: Int) -> Date {
        let remainingBlocks = expiryBlock - currentBlock
        // ~14400 blocks per day (6 seconds per block)
        let remainingDays = Int(remainingBlocks / blocksPerDay)

        let currentDate = Date()
        var expiryDate = Calendar.current.date(byAdding: .day, value: remainingDays, to: currentDate) ?? Date()

        if extendedByYears > 0 {
            expiryDate = Calendar.current.date(byAdding: .year, value: extendedByYears, to: expiryDate) ?? Date()
        }

        return expiryDate
    }
}
