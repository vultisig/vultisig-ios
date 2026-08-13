//
//  UnmergeShares.swift
//  VultisigApp
//
//  Exact human-decimal → base-unit conversion for RUJI merge shares.
//
//  Deliberately formatter-free. The obvious spelling — `value.toDecimal()`,
//  or any `NumberFormatter.number(from:)` — hands back an `NSNumber` backed by
//  a `Double` (the formatter's `generatesDecimalNumbers` is off), so a share
//  count past ~15 significant digits has already lost its low-order digits
//  before any arithmetic happens. The unmerge memo is the only thing that
//  carries the share count to the contract, so a rounded digit here is a
//  withdrawal of the wrong amount.
//

import BigInt
import Foundation

enum UnmergeShares {
    /// RUJI merge shares are denominated in fixed 1e8 base units, independent
    /// of the merged token's own `decimals`.
    static let decimals: Int = 8

    /// Parses a human-decimal share amount into base units, exactly.
    ///
    /// Reads the locale's own separators and nothing else: its decimal
    /// separator, and its grouping separator **only where the digits are
    /// actually grouped** (see `ungrouped(_:separator:)`). An amount written in
    /// some other locale's convention is refused rather than reinterpreted —
    /// `NumberFormatter` reinterprets it, and on this path that means
    /// withdrawing ten times what was asked for.
    ///
    /// Fraction digits past `decimals` are **truncated**, not rounded. Legacy
    /// rounded (`%.0f`), which could scale an amount typed at the exact
    /// available balance up to more shares than the account holds; rounding down
    /// can only ever leave dust behind.
    static func parse(_ text: String, decimals: Int = Self.decimals, locale: Locale = .current) -> BigInt? {
        let decimalSeparator = locale.decimalSeparator ?? "."
        let groupingSeparator = locale.groupingSeparator ?? ","

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isNotEmpty else { return nil }

        // Split on the decimal separator BEFORE touching grouping: a locale that
        // groups with "." and one that uses "." as its decimal point are
        // distinguished by which of the two this string is measured against, and
        // stripping first would erase the distinction.
        let sides = trimmed.components(separatedBy: decimalSeparator)
        guard sides.count <= 2,
              let integerDigits = ungrouped(sides[0], separator: groupingSeparator) else {
            return nil
        }

        // "5." is a legal mid-entry keypad state and means the same as "5".
        let fraction = sides.count == 2 ? sides[1] : ""
        guard fraction.isEmpty || isASCIIDigits(fraction) else { return nil }

        let truncated = String(fraction.prefix(decimals))
        let padded = truncated.padding(toLength: decimals, withPad: "0", startingAt: 0)
        return BigInt(integerDigits + padded)
    }

    /// The base-unit count as a human decimal, for display and for the amount
    /// field's ceiling.
    ///
    /// `BigInt` → digit string → `Decimal`, so no `Double` is involved, but
    /// `Decimal` tops out around 38 significant digits: a share count larger
    /// than that loses its tail here. The ceiling that decides what can actually
    /// be withdrawn is the raw `BigInt`, never this value, so the consequence of
    /// that limit is a maximum that offers slightly too little — not one that
    /// offers shares the account does not hold.
    static func decimalValue(of shares: BigInt, decimals: Int = Self.decimals) -> Decimal {
        let divisor = pow(Decimal(10), decimals)
        return (Decimal(string: shares.description) ?? .zero) / divisor
    }

    /// The integer side with its grouping separators removed — but only when
    /// they are placed where that locale actually groups: the first group of one
    /// to three digits, every later group of exactly three.
    ///
    /// A lone separator followed by one or two digits is not grouping. In an
    /// `en_US` field `1,5` is someone writing a comma-decimal amount, and in a
    /// `de_DE` field `1.5` is someone writing a dot-decimal one; dropping the
    /// separator turns either into `15` and withdraws ten times what was
    /// intended. Both are refused, and the form says the amount is invalid.
    private static func ungrouped(_ side: String, separator: String) -> String? {
        // An empty integer side is the ".5" keypad state.
        guard side.isNotEmpty else { return "0" }
        guard separator.isNotEmpty, side.contains(separator) else {
            return isASCIIDigits(side) ? side : nil
        }

        let groups = side.components(separatedBy: separator)
        guard groups.allSatisfy(isASCIIDigits),
              let first = groups.first,
              (1...3).contains(first.count),
              groups.dropFirst().allSatisfy({ $0.count == 3 }) else {
            return nil
        }
        return groups.joined()
    }

    private static func isASCIIDigits(_ string: String) -> Bool {
        !string.isEmpty && string.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
