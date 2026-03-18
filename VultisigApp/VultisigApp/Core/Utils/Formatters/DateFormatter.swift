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

    static func formatMonthDayYear(_ date: Date) -> String {
        monthDayYear.string(from: date)
    }

    static func formatMonthDayYear(_ timeInterval: TimeInterval) -> String {
        monthDayYear.string(from: Date(timeIntervalSince1970: timeInterval))
    }
}
