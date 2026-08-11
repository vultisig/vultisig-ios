//
//  WithdrawMinimumAmountValidator.swift
//  VultisigApp
//

import Foundation

/// Rejects a withdrawal too small for a fractional-withdrawal memo to express.
///
/// `AmountBalanceValidator` already refuses zero, negative and over-balance
/// amounts, but it has no idea the memo addresses the position in ten-thousandths
/// (see `WithdrawBasisPoints`). A small *positive* amount clears it and then rounds
/// away to a `:0` memo — a transaction that pays a fee to withdraw nothing. On the
/// 2002.74 TCY position this was reported against, anything under about 0.20 TCY
/// does that.
///
/// Paired with `AmountBalanceValidator` on the amount field, so the existing form
/// machinery surfaces the message and blocks Continue rather than the builder
/// silently returning `nil` and leaving a dead button.
struct WithdrawMinimumAmountValidator: FormFieldValidator {
    static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        return formatter
    }()

    /// Enough digits that the quoted minimum is a figure the user can actually
    /// type, however small the position.
    static let quotedDigits = 8

    let available: Decimal
    let ticker: String

    enum ValidationError: LocalizedError {
        case belowMinimum(minimum: String, ticker: String)

        var errorDescription: String? {
            switch self {
            case .belowMinimum(let minimum, let ticker):
                return String(format: "withdrawBelowMinimum".localized, minimum, ticker)
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

        // Compared against the EXACT threshold, quoted at display precision.
        // Comparing against the rounded-up figure instead would make a position
        // smaller than that figure impossible to close at all.
        guard amount >= WithdrawBasisPoints.minimumAmount(forAvailable: available) else {
            let quoted = WithdrawBasisPoints.quotedMinimum(forAvailable: available, digits: Self.quotedDigits)
            throw ValidationError.belowMinimum(
                minimum: quoted.formatToDecimal(digits: Self.quotedDigits),
                ticker: ticker
            )
        }
    }
}
