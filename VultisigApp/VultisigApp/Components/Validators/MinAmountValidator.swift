//
//  MinAmountValidator.swift
//  VultisigApp
//

import Foundation

/// Fails when a non-empty, non-zero entered amount is below `minimum`. An empty
/// value passes (pair with `RequiredValidator`), so the form only invalidates
/// once the user has typed an amount under the minimum.
struct MinAmountValidator: FormFieldValidator {
    let minimum: Decimal
    let errorMessage: String

    func validate(value: String) throws {
        guard value.isNotEmpty else { return }

        guard
            let number = AmountBalanceValidator.formatter.number(from: value),
            let amount = Decimal(string: number.stringValue)
        else {
            // Defer malformed-input reporting to the other validators.
            return
        }

        // A zero / empty-equivalent amount is the "nothing entered yet" case;
        // AmountBalanceValidator owns the zero error.
        guard amount > 0 else { return }

        guard amount >= minimum else {
            throw HelperError.runtimeError(errorMessage)
        }
    }
}
