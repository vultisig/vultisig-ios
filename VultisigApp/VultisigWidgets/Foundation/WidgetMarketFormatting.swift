//
//  WidgetMarketFormatting.swift
//  VultisigWidgets
//

import Foundation

enum WidgetMarketFormatting {
    static func price(_ value: Double, currency: String, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.uppercased()
        formatter.locale = locale
        formatter.usesGroupingSeparator = true

        switch abs(value) {
        case 1...:
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        case 0.01..<1:
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 4
        default:
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 8
        }

        return formatter.string(from: NSNumber(value: value)) ?? "—"
    }

    static func change(_ value: Double?, locale: Locale = .current) -> String {
        guard let value, value.isFinite else { return "— 24H" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.locale = locale
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.positivePrefix = "+"
        let formatted = formatter.string(from: NSNumber(value: value / 100)) ?? "—"
        return "\(formatted) 24H"
    }
}
