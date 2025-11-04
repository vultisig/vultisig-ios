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
        case exceedsBalance
        
        var errorDescription: String? {
            switch self {
            case .invalidAmount:
                return "invalidAmount".localized
            case .exceedsBalance:
                return "amountExceeded".localized
            }
        }
    }
    
    func validate(value: String) throws {
        let amount: Decimal
        
        if let number = Self.formatter.number(from: value) {
            amount = Decimal(string: number.stringValue) ?? 0
        } else {
            throw ValidationError.invalidAmount
        }
        
        guard amount > 0, amount <= balance else {
            throw ValidationError.exceedsBalance
        }
    }
}
