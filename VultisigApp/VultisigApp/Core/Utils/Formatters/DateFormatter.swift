//
//  DateFormatter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/10/2025.
//

import Foundation

enum CustomDateFormatter {
    static let monthDayYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yy"
        return formatter
    }()

    /// Four-digit year, used by the rewards-history sheet's dated rows
    /// (issue calls for `MMM d, yyyy`, distinct from the card's `yy`).
    static let monthDayFullYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    static func formatMonthDayYear(_ date: Date) -> String {
        monthDayYear.string(from: date)
    }

    static func formatMonthDayYear(_ timeInterval: TimeInterval) -> String {
        monthDayYear.string(from: Date(timeIntervalSince1970: timeInterval))
    }

    static func formatMonthDayFullYear(_ date: Date) -> String {
        monthDayFullYear.string(from: date)
    }
}
