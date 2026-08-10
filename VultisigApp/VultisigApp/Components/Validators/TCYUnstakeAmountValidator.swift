//
//  TCYUnstakeAmountValidator.swift
//  VultisigApp
//

import Foundation

/// Rejects a TCY withdrawal too small for the `tcy-:<bps>` memo to express.
///
/// `AmountBalanceValidator` already refuses zero, negative and over-balance
/// amounts, but it has no idea the memo addresses the position in ten-thousandths.
/// A small *positive* amount clears it and then rounds away to `tcy-:0` — a
/// transaction that pays a fee to withdraw nothing. On a 2002.74 TCY position
/// anything under about 0.20 TCY does this.
///
/// Paired with `AmountBalanceValidator` on the amount field, so the existing form
/// machinery surfaces the message and blocks Continue rather than the builder
/// silently returning `nil` and leaving a dead button.
struct TCYUnstakeAmountValidator: FormFieldValidator {
    static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        return formatter
    }()

    let available: Decimal
    let ticker: String

    enum ValidationError: LocalizedError {
        case belowMinimum(minimum: String, ticker: String)

        var errorDescription: String? {
            switch self {
            case .belowMinimum(let minimum, let ticker):
                return String(format: "tcyUnstakeBelowMinimum".localized, minimum, ticker)
            }
        }
    }

    func validate(value: String) throws {
        // A value this validator cannot read is not its call to make —
        // `AmountBalanceValidator` reports malformed input, and reporting it
        // twice would put two different errors on one field.
        guard
            let number = Self.formatter.number(from: value),
            let amount = Decimal(string: number.stringValue),
            amount > 0,
            available > 0
        else {
            return
        }

        let minimum = TCYUnstakeBasisPoints.minimumAmount(forAvailable: available)
        guard amount >= minimum else {
            throw ValidationError.belowMinimum(
                minimum: minimum.formatToDecimal(digits: 4),
                ticker: ticker
            )
        }
    }
}
