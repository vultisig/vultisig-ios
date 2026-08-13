//
//  IBCTransferAmount.swift
//  VultisigApp
//
//  Reading the transfer amount out of the field, exactly, or refusing to read
//  it at all.
//
//  The shared amount path goes through `NumberFormatter.number(from:)`, which
//  never refuses: handed `1,5` in an `en_US` field it drops the comma as a
//  grouping separator and returns **15**. The same string is what someone
//  writing a comma-decimal amount types, and what pasting from a comma-decimal
//  source produces. On a send path that is a ten-fold transfer the user never
//  asked for.
//
//  So grouping is honoured only where the locale actually groups — the first
//  group is one to three digits, every later group is exactly three — and
//  anything else is refused. A refused amount shows the field's error; a
//  reinterpreted one moves money.
//

import Foundation

enum IBCTransferAmount {

    /// Parses a human-decimal amount, or `nil` when the text is not
    /// unambiguously one.
    ///
    /// Fraction digits past `decimals` are **truncated**, not rounded: the
    /// chain cannot represent them, and rounding up an amount typed at the
    /// exact spendable balance would put it over.
    static func parse(_ text: String, decimals: Int, locale: Locale = .current) -> Decimal? {
        let decimalSeparator = locale.decimalSeparator ?? "."
        let groupingSeparator = locale.groupingSeparator ?? ","

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isNotEmpty else { return nil }

        // Split on the decimal separator BEFORE touching grouping. A locale that
        // groups with "." and one whose decimal point is "." are told apart only
        // by which of the two this string is measured against; stripping
        // grouping first erases that distinction.
        let sides = trimmed.components(separatedBy: decimalSeparator)
        // A decimal separator anywhere settles what the *other* separator is, so
        // its presence is what makes a single group boundary readable at all.
        guard sides.count <= 2,
              let integerDigits = ungrouped(
                  sides[0],
                  separator: groupingSeparator,
                  hasDecimalSeparator: sides.count == 2
              ) else {
            return nil
        }

        // "5." is a legal mid-entry keypad state and means "5".
        let fraction = sides.count == 2 ? sides[1] : .empty
        guard fraction.isEmpty || isASCIIDigits(fraction) else { return nil }

        let truncated = String(fraction.prefix(max(decimals, 0)))
        // Assembled as an unscaled integer and then shifted, so no intermediate
        // `Double` is involved: `Decimal(string:)` on a digit string is exact.
        guard let units = Decimal(string: integerDigits + truncated) else { return nil }
        return units / pow(Decimal(10), truncated.count)
    }

    /// Renders an amount in the one spelling this parser always reads back:
    /// the locale's decimal separator, **no grouping separators at all**,
    /// truncated to `decimals`.
    ///
    /// Used for text the app itself generates — the amount field's percentage
    /// presets, which otherwise emit `Decimal.formatToDecimal(digits:)` output
    /// and so can produce exactly the `1,000` shape `parse` refuses. Provenance
    /// is what makes re-rendering safe here: that value came from a `Decimal`
    /// the app already had, not from a string whose author's locale is unknown.
    static func plainSpelling(of amount: Decimal, decimals: Int, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = max(decimals, 0)
        formatter.minimumFractionDigits = 0
        // Match `formatToDecimal`: never round an amount UP past the ceiling it
        // was derived from.
        formatter.roundingMode = .down
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? .empty
    }

    /// The integer side with its grouping separators removed, but only when the
    /// string says unambiguously that they *are* grouping separators.
    ///
    /// Two refusals, both of them amounts this form must not guess at:
    ///
    /// - **Wrong placement.** A lone separator followed by one or two digits is
    ///   not grouping. In an `en_US` field `1,5` is someone writing a
    ///   comma-decimal amount and in a `de_DE` field `1.5` is someone writing a
    ///   dot-decimal one; dropping the separator sends ten times the intention.
    /// - **A single group boundary with no decimal separator to disambiguate
    ///   it.** `1,000` in `en_US` is one thousand if the separator groups, and
    ///   *one* if it was written by someone whose decimal separator is a comma.
    ///   Both readings are well-formed, so the string simply does not say which,
    ///   and guessing wrong here is a 1000× transfer. Two or more boundaries
    ///   (`1,234,567`) cannot be a decimal point, and a string that also carries
    ///   the decimal separator (`1,234.5`) has already named it — those are
    ///   unambiguous and are accepted.
    ///
    /// The cost is that "MAX" on a balance that formats to an exact `X,YYY` with
    /// no fraction reads as invalid until the user retypes it without the
    /// separator. For a native asset the fee reserve makes the ceiling a
    /// non-integer, so this is close to unreachable there; refusing is the right
    /// side to err on regardless.
    private static func ungrouped(
        _ side: String,
        separator: String,
        hasDecimalSeparator: Bool
    ) -> String? {
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

        // Exactly one boundary and nothing else in the string to settle it.
        guard hasDecimalSeparator || groups.count > 2 else { return nil }

        return groups.joined()
    }

    private static func isASCIIDigits(_ string: String) -> Bool {
        !string.isEmpty && string.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

/// Amount validator for the IBC form.
///
/// Deliberately not `AmountBalanceValidator`: that one accepts what
/// `NumberFormatter` accepts, so the field would pass `1,5` while the builder —
/// which has to be strict, it is what signs — refuses it, and Continue would do
/// nothing with no error shown. Field and builder read the amount the same way.
struct IBCTransferAmountValidator: FormFieldValidator {
    let balance: Decimal
    let decimals: Int
    let locale: Locale

    init(balance: Decimal, decimals: Int, locale: Locale = .current) {
        self.balance = balance
        self.decimals = decimals
        self.locale = locale
    }

    enum ValidationError: LocalizedError {
        case invalidAmount
        case zeroAmount
        case exceedsBalance

        var errorDescription: String? {
            switch self {
            case .invalidAmount:
                return "invalidAmount".localized
            case .zeroAmount:
                return "amountCannotBeZero".localized
            case .exceedsBalance:
                return "amountExceeded".localized
            }
        }
    }

    func validate(value: String) throws {
        guard let amount = IBCTransferAmount.parse(value, decimals: decimals, locale: locale) else {
            throw ValidationError.invalidAmount
        }
        guard amount >= 0 else { throw ValidationError.invalidAmount }
        guard amount > 0 else { throw ValidationError.zeroAmount }
        guard amount <= balance else { throw ValidationError.exceedsBalance }
    }
}
