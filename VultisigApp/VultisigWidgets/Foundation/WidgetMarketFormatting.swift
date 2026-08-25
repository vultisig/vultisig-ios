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
        guard let value, value.isFinite else {
            return String(localized: "widget.changeUnavailableDisplay")
        }
        let formatter = percentageFormatter(locale: locale)
        formatter.positivePrefix = "+"
        let percentage = formatter.string(from: NSNumber(value: value / 100)) ?? "—"
        return String(
            format: String(localized: "widget.change"),
            locale: locale,
            percentage
        )
    }

    static func accessibilityChange(_ value: Double?, locale: Locale = .current) -> String {
        guard let value, value.isFinite else {
            return String(localized: "widget.changeUnavailable")
        }
        let direction = value >= 0
            ? String(localized: "widget.up")
            : String(localized: "widget.down")
        return String(
            format: String(localized: "widget.accessibility.change"),
            locale: locale,
            direction,
            compactChange(value, locale: locale)
        )
    }

    static func compactChange(_ value: Double?, locale: Locale = .current) -> String {
        guard let value, value.isFinite else { return "—" }
        let formatter = percentageFormatter(locale: locale)
        formatter.positivePrefix = ""
        return formatter.string(from: NSNumber(value: abs(value) / 100)) ?? "—"
    }

    private static func percentageFormatter(locale: Locale) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.locale = locale
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }
}
