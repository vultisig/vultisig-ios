//
//  SwapReworkFormat.swift
//  VultisigApp
//
//  Token amounts on the reworked form. Grouping "," and decimals "." in every
//  locale, matching the keypad, so a German user never sees "0,5" above a
//  keypad that types "0.5". Fiat keeps the app's currency formatting.
//

import Foundation

enum SwapReworkFormat {
    /// Up to eight significant digits: "0.0140218", "1.28367", "12,000".
    static func amount(_ value: Decimal, maxFractionDigits: Int = 8) -> String {
        guard value != 0 else { return "0" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.roundingMode = .down
        if abs(value) >= 1 {
            let integerDigits = String(describing: NSDecimalNumber(decimal: abs(value)).intValue).count
            formatter.maximumFractionDigits = max(0, min(maxFractionDigits, 8 - integerDigits))
        } else {
            formatter.usesSignificantDigits = true
            formatter.maximumSignificantDigits = 6
            formatter.minimumSignificantDigits = 1
        }
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0"
    }

    static func amount(_ value: Decimal, ticker: String) -> String {
        "\(amount(value)) \(ticker)"
    }

    /// "8-12 min", "~45 s", from a provider estimate in seconds.
    static func eta(seconds: Int) -> String {
        guard seconds >= 60 else { return String(format: "swapReworkEtaSeconds".localized, max(seconds, 1)) }
        let minutes = Double(seconds) / 60
        let low = max(1, Int((minutes * 0.8).rounded(.down)))
        let high = max(low + 1, Int((minutes * 1.2).rounded(.up)))
        return String(format: "swapReworkEtaMinutes".localized, low, high)
    }
}
