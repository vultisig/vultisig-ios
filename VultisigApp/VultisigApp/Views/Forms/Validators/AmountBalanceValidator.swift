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
