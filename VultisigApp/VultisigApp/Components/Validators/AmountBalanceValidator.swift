//
//  AmountBalanceValidator.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/11/2025.
//

import Foundation

struct AmountBalanceValidator: FormFieldValidator {
    static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        return formatter
    }()

    let balance: Decimal

    enum ValidationError: LocalizedError {
        case invalidAmount
        case zeroAmount
        case exceedsBalance

        var errorDescription: String? {
            switch self {
            case .invalidAmount:
                return "invalidAmount".localized
            case .exceedsBalance:
                return "amountExceeded".localized
            case .zeroAmount:
                return "amountCannotBeZero".localized
            }
        }
    }

    func validate(value: String) throws {
        // `formatter` is a plain `.decimal` NumberFormatter, which reads scientific
        // notation: "1e5" would validate as 100000 and ride into the transaction
        // builder. The balance ceiling below is not a backstop for that — a large
        // enough balance, or a small exponent, clears it.
        guard value.isValidDecimal() else {
            throw ValidationError.invalidAmount
        }

        guard
            let number = Self.formatter.number(from: value),
            let amount = Decimal(string: number.stringValue)
        else {
            throw ValidationError.invalidAmount
        }

        if amount < 0 {
            throw ValidationError.invalidAmount
        }

        if amount == 0 {
            throw ValidationError.zeroAmount
        }

        guard amount <= balance else {
            throw ValidationError.exceedsBalance
        }
    }
}
