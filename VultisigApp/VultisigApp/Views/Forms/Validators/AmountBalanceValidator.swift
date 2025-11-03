//
//  AmountBalanceValidator.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/11/2025.
//

import Foundation

struct AmountBalanceValidator: FormFieldValidator {
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
        guard let amount = Decimal(string: value) else {
            throw ValidationError.invalidAmount
        }
        
        guard amount > 0, amount <= balance else {
            throw ValidationError.exceedsBalance
        }
    }
}
