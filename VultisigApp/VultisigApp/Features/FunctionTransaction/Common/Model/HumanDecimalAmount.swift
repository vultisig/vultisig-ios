//
//  HumanDecimalAmount.swift
//  VultisigApp
//
//  Strict human-decimal parsing for a form's amount field.
//
//  Deliberately not `String.parseInput()`. That helper tries the current
//  locale's `NumberFormatter` and then falls back to `en_US`, and a
//  `NumberFormatter` reinterprets an amount written in the other convention
//  rather than refusing it: `1,5` reads as fifteen in `en_US`, and `1.5` reads
//  as fifteen in `de_DE`. An amount attached to a transaction is real funds, so
//  a reinterpreted separator is a ten-times send from a paste.
//
//  This parser reads the locale's own separators and nothing else, and returns
//  nil for anything ambiguous so the form can say the amount is invalid.
//
//  The algorithm is the Cosmos SWITCH form's, ported verbatim rather than
//  re-derived — four locale defects were found writing it the first time. It is
//  named for what it does rather than for one caller so the two forms share a
//  single copy once both are on this architecture.
//
//  **The residual, stated plainly.** Grouping that is well formed *in the locale
//  in force* is accepted, so an `en_US` field reads `1,000` as one thousand —
//  which is what it means in `en_US`, and also what a `de_DE` user's `1.000`
//  means in theirs. A cross-locale PASTE of the other convention's `1,000`
//  (meaning one) therefore still reads as a thousand. That case is not fixable
//  here: the percentage and max buttons fill this field from
//  `Decimal.formatToDecimal(digits:)`, which emits grouped digits, so refusing
//  grouping outright would leave any user with a balance over a thousand unable
//  to submit their own maximum. Closing it means making that shared formatter
//  emit ungrouped digits app-wide, which is a change to every amount field, not
//  to this parser. The shapes that are ambiguous *within* one convention —
//  `1,5`, `0,500`, an Indian two-group `123,456` — are all refused below.
//

import Foundation

enum HumanDecimalAmount {

    /// Parses a human-decimal amount in `locale`'s convention, or nil when the
    /// string is not unambiguously a number in that convention.
    ///
    /// Fraction digits past `decimals` are **truncated**, never rounded: this
    /// value is compared against the wallet balance, and rounding up at the
    /// ceiling would build a transfer of slightly more than the balance holds.
    static func parse(_ text: String, decimals: Int, locale: Locale = .current) -> Decimal? {
        let decimalSeparator = locale.decimalSeparator ?? "."
        let groupingSeparator = locale.groupingSeparator ?? ","

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isNotEmpty else { return nil }

        // Split on the decimal separator BEFORE touching grouping: a locale
        // that groups with "." and one that uses "." as its decimal point are
        // told apart only by which of the two this string is measured against,
        // and stripping grouping first would erase the distinction.
        let sides = trimmed.components(separatedBy: decimalSeparator)
        guard sides.count <= 2,
              let integerDigits = ungrouped(
                  sides[0],
                  separator: groupingSeparator,
                  sizes: groupSizes(for: locale)
              ) else {
            return nil
        }

        // "5." is a legal mid-entry keypad state and means the same as "5".
        let rawFraction = sides.count == 2 ? sides[1] : ""
        let fraction: String
        if rawFraction.isEmpty {
            fraction = ""
        } else if let digits = decimalDigits(rawFraction) {
            fraction = digits
        } else {
            return nil
        }

        // Both sides are plain ASCII digit runs by here, so `Decimal(string:)`
        // never sees a separator and cannot read one under the machine's own
        // locale. The two halves are recombined arithmetically for the same
        // reason.
        let truncated = String(fraction.prefix(max(decimals, 0)))
        guard let integerValue = Decimal(string: integerDigits) else { return nil }
        guard truncated.isNotEmpty else { return integerValue }
        guard let fractionValue = Decimal(string: truncated) else { return nil }
        return integerValue + fractionValue / pow(Decimal(10), truncated.count)
    }

    /// How wide `locale`'s digit groups are: the trailing group's width, and the
    /// width of every group before it. They differ in the Indian system, where
    /// `12,34,567` is well formed — a rule hard-coded to threes would reject a
    /// user's own "max" amount, since the field is filled by a formatter reading
    /// the same locale.
    private static func groupSizes(for locale: Locale) -> (trailing: Int, leading: Int) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        let trailing = formatter.groupingSize > 0 ? formatter.groupingSize : 3
        let leading = formatter.secondaryGroupingSize > 0 ? formatter.secondaryGroupingSize : trailing
        return (trailing, leading)
    }

    /// The integer side with its grouping separators removed — but only where
    /// that locale actually groups.
    ///
    /// A separator that is not in a grouping position is not grouping. In an
    /// `en_US` field `1,5` is someone writing a comma-decimal amount, and in a
    /// `de_DE` field `1.5` is someone writing a dot-decimal one; dropping the
    /// separator turns either into `15`. Both are refused.
    ///
    /// The leading-zero rule catches the case that survives a width check:
    /// `0,500` has group widths a grouped `en_US` number would have, but nobody
    /// writes five hundred that way — it is half, written in a comma-decimal
    /// convention, and stripping the separator would send five hundred times the
    /// intended amount.
    private static func ungrouped(_ side: String, separator: String, sizes: (trailing: Int, leading: Int)) -> String? {
        // An empty integer side is the ".5" keypad state.
        guard side.isNotEmpty else { return "0" }
        guard separator.isNotEmpty, side.contains(separator) else {
            return decimalDigits(side)
        }

        let rawGroups = side.components(separatedBy: separator)
        let groups = rawGroups.compactMap { decimalDigits($0) }
        guard groups.count == rawGroups.count,
              groups.count >= 2,
              let first = groups.first,
              let last = groups.last,
              last.count == sizes.trailing,
              groups.dropFirst().dropLast().allSatisfy({ $0.count == sizes.leading }),
              // The leading group is the remainder, so it may be short — but
              // never empty, and never wider than a full group of its own rank.
              // Measured against `leading`, not `trailing`: in the Indian system
              // those differ, and `123,456` is not how 123456 is written there —
              // it is far more likely a comma-decimal `123.456` pasted in, which
              // stripping the separator would turn into a thousand-times send.
              (1...sizes.leading).contains(first.count),
              !first.hasPrefix("0") else {
            return nil
        }
        return groups.joined()
    }

    /// `string` rewritten in ASCII digits, or nil if any character is not a
    /// decimal digit.
    ///
    /// Not an ASCII-only check: a locale's numbering system may be non-Latin
    /// (Arabic-Indic, Devanagari, …), and `Decimal.formatToDecimal(digits:)` —
    /// what the percentage buttons write into the field — emits whatever digits
    /// that locale uses. Refusing them would leave those users unable to submit
    /// their own "max" amount.
    ///
    /// The test is Unicode's `decimal` numeric type, which is exactly the set a
    /// numbering system uses positionally. It admits `٥` and `५` and rejects
    /// `²`, `½` and `Ⅻ`, each of which carries a numeric value that would
    /// otherwise fold into a digit and change the amount.
    private static func decimalDigits(_ string: String) -> String? {
        guard !string.isEmpty else { return nil }
        var result = ""
        result.reserveCapacity(string.count)
        for character in string {
            guard character.unicodeScalars.count == 1,
                  let scalar = character.unicodeScalars.first,
                  scalar.properties.numericType == .decimal,
                  let value = character.wholeNumberValue,
                  (0...9).contains(value) else {
                return nil
            }
            result.append(String(value))
        }
        return result
    }
}
