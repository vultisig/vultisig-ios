//
//  DecimalExtension.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 08/04/2024.
//

import Foundation
import SwiftUI
import BigInt

extension Decimal {

    func truncated(toPlaces places: Int) -> Decimal {
        var original = self
        var truncated = Decimal()
        NSDecimalRound(&truncated, &original, places, .down)
        return truncated
    }

    /// Base method for formatting fiat values with configurable decimal places
    private func formatToFiat(includeCurrencySymbol: Bool = true, maximumFractionDigits: Int, roundingMode: NumberFormatter.RoundingMode = .down) -> String {
        let formatter = NumberFormatter()
        if includeCurrencySymbol {
            formatter.numberStyle = .currency
            formatter.currencyCode = SettingsCurrency.current.rawValue
        } else {
            formatter.numberStyle = .decimal
        }
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.minimumFractionDigits = 2
        formatter.decimalSeparator = Locale.current.decimalSeparator ?? "."
        formatter.groupingSeparator = Locale.current.groupingSeparator ?? ","
        formatter.roundingMode = roundingMode

        let number = NSDecimalNumber(decimal: self)
        return formatter.string(from: number) ?? ""
    }

    /// Format fiat value with standard 2 decimal places
    func formatToFiat(includeCurrencySymbol: Bool = true) -> String {
        return formatToFiat(includeCurrencySymbol: includeCurrencySymbol, maximumFractionDigits: 2)
    }

    /// Format fiat value for fee display with more decimal places to show small fees
    func formatToFiatForFee(includeCurrencySymbol: Bool = true) -> String {
        return formatToFiat(includeCurrencySymbol: includeCurrencySymbol, maximumFractionDigits: 5)
    }

    /// Format a per-token unit price, revealing the significant figures of a sub-cent price instead
    /// of collapsing it to the currency's standard 2 decimal places. Prices of one cent or more, and
    /// zero, use standard formatting. Below one cent the significant figures are preserved and, once
    /// there are four or more zeros between the decimal point and the first significant digit, those
    /// zeros collapse into compact subscript notation — e.g. `0.00000003` renders as `$0.0₇3` and
    /// `0.00001234` as `$0.0₄1234`, while `0.0001234` (fewer zeros) stays `$0.0001234`. This mirrors
    /// the shared TypeScript price formatter so iOS matches the desktop app and browser extension.
    ///
    /// The subscript count uses Unicode subscript digits (`₀`–`₉`) as the plain-string baseline;
    /// render the result with `CompactAmountText` to upgrade that count into a legibly sized subscript.
    func formatToFiatPrice(includeCurrencySymbol: Bool = true) -> String {
        let subUnit = Decimal(sign: .plus, exponent: -2, significand: 1)
        let absValue = abs(self)
        guard absValue > 0, absValue < subUnit else {
            return formatToFiat(includeCurrencySymbol: includeCurrencySymbol)
        }
        return formatTinyFiatPrice(absValue: absValue, isNegative: self < 0, includeCurrencySymbol: includeCurrencySymbol)
    }

    private func formatTinyFiatPrice(absValue: Decimal, isNegative: Bool, includeCurrencySymbol: Bool) -> String {
        // Reveal up to `significantDigits` significant figures, rounding half-up. The fraction-digit
        // count is estimated from the pre-rounded value; a rounding carry (e.g. 0.000099999 -> 0.0001)
        // only shrinks the zero run, which the formatted output already reflects.
        let fractionDigits = Self.leadingFractionalZeros(of: absValue) + PriceFormatting.significantDigits

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.decimalSeparator = "."
        formatter.maximumFractionDigits = fractionDigits
        formatter.minimumFractionDigits = 0
        formatter.roundingMode = .halfUp

        guard let plain = formatter.string(from: NSDecimalNumber(decimal: absValue)), plain.hasPrefix("0.") else {
            return formatToFiat(includeCurrencySymbol: includeCurrencySymbol)
        }
        let fraction = String(plain.dropFirst(2))
        let significantDigits = String(fraction.drop(while: { $0 == "0" }))
        guard !significantDigits.isEmpty else {
            return formatToFiat(includeCurrencySymbol: includeCurrencySymbol)
        }

        let leadingZeros = fraction.count - significantDigits.count
        let decimals = leadingZeros >= PriceFormatting.subscriptThreshold
            ? "0" + Self.subscriptString(leadingZeros) + significantDigits
            : String(repeating: "0", count: leadingZeros) + significantDigits

        let separator = Locale.current.decimalSeparator ?? "."
        let affixes = includeCurrencySymbol ? Self.currencyAffixes() : (prefix: "", suffix: "")
        let sign = isNegative ? "-" : ""
        return sign + affixes.prefix + "0" + separator + decimals + affixes.suffix
    }

    /// Number of zeros between the decimal point and the first significant digit of a value in (0, 1).
    private static func leadingFractionalZeros(of value: Decimal) -> Int {
        var scaled = value
        var firstSignificantPlace = 0
        while scaled < 1 {
            scaled *= 10
            firstSignificantPlace += 1
        }
        return max(firstSignificantPlace - 1, 0)
    }

    /// The currency symbol and its locale-specific placement, captured as the text that surrounds the
    /// number, so a custom numeric string can be injected while keeping e.g. "$" prefixed or " kr"
    /// suffixed. Mirrors the SDK's `Intl.NumberFormat.formatToParts` approach.
    private static func currencyAffixes() -> (prefix: String, suffix: String) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = SettingsCurrency.current.rawValue
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        guard let zero = formatter.string(from: 0),
              let digitRange = zero.rangeOfCharacter(from: .decimalDigits) else {
            return ("", "")
        }
        return (String(zero[..<digitRange.lowerBound]), String(zero[digitRange.upperBound...]))
    }

    private static func subscriptString(_ value: Int) -> String {
        let glyphs: [Character] = ["₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉"]
        return String(String(value).compactMap { character in
            character.wholeNumberValue.map { glyphs[$0] }
        })
    }

    private enum PriceFormatting {
        static let significantDigits = 4
        static let subscriptThreshold = 4
    }

    func formatDecimalToLocale(locale: Locale = Locale.current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.maximumFractionDigits = 8
        formatter.minimumFractionDigits = 0
        formatter.roundingMode = .down
        return formatter.string(from: self as NSDecimalNumber) ?? ""
    }

    /// Format large numbers with abbreviations (M, B, T) for DISPLAY ONLY
    /// ⚠️ NEVER use in input fields - only for displaying values
    func formatWithAbbreviation(maxDecimals: Int = 2) -> String {
        let absValue = abs(self)
        let isNegative = self < 0
        let prefix = isNegative ? "-" : ""

        let trillion = Decimal(1_000_000_000_000)
        let billion = Decimal(1_000_000_000)
        let million = Decimal(1_000_000)
        let thousand = Decimal(1_000)

        if absValue >= trillion {
            let value = (absValue / trillion).truncated(toPlaces: maxDecimals)
            return "\(prefix)\(value.formatToDecimal(digits: maxDecimals))T"
        } else if absValue >= billion {
            let value = (absValue / billion).truncated(toPlaces: maxDecimals)
            return "\(prefix)\(value.formatToDecimal(digits: maxDecimals))B"
        } else if absValue >= million {
            let value = (absValue / million).truncated(toPlaces: maxDecimals)
            return "\(prefix)\(value.formatToDecimal(digits: maxDecimals))M"
        } else if absValue >= thousand {
            let value = (absValue / thousand).truncated(toPlaces: maxDecimals)
            return "\(prefix)\(value.formatToDecimal(digits: maxDecimals))K"
        } else {
            return "\(prefix)\(absValue.formatToDecimal(digits: maxDecimals))"
        }
    }

    func formatToDecimal(digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = digits
        formatter.minimumFractionDigits = 0
        formatter.decimalSeparator = Locale.current.decimalSeparator ?? "."
        formatter.groupingSeparator = Locale.current.groupingSeparator ?? ","
        formatter.roundingMode = .down

        // Convert Decimal to NSDecimalNumber before using with NumberFormatter
        let number = NSDecimalNumber(decimal: self)

        return formatter.string(from: number) ?? ""
    }

    /// Format values ​​for display, automatically using abbreviations for large values
    /// For values ​​>= 1M, use abbreviations (K, M, B, T)
    /// For values ​​< 1M, use standard decimal formatting with locale
    /// ⚠️ ONLY for display - never use in input fields
    func formatForDisplay(maxDecimals: Int = 2, locale: Locale = Locale.current, skipAbbreviation: Bool = false) -> String {
        let million = Decimal(1_000_000)

        if abs(self) >= million, !skipAbbreviation {
            return formatWithAbbreviation(maxDecimals: maxDecimals)
        } else {
            return formatDecimalToLocale(locale: locale)
        }
    }

    init(_ bigInt: BigInt) {
        self = .init(string: bigInt.description) ?? 0
    }

    func toInt() -> Int {
        return NSDecimalNumber(decimal: self).intValue
    }
}
