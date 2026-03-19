//
//  LPUnitsValidator.swift
//  VultisigApp
//
//  Created by Claude Code on 30/12/2025.
//

import Foundation

/// Validator for LP units that checks against available balance
struct LPUnitsValidator: FormFieldValidator {
    let availableUnits: String

    enum ValidationError: LocalizedError {
        case invalidUnits
        case zeroUnits
        case exceedsAvailable(available: String)

        var errorDescription: String? {
            switch self {
            case .invalidUnits:
                return "invalidLPUnits".localized
            case .zeroUnits:
                return "lpUnitsCannotBeZero".localized
            case .exceedsAvailable(let available):
                return String(format: "lpUnitsExceeded".localized, available)
            }
        }
    }

    func validate(value: String) throws {
        guard !value.isEmpty else { return }

        guard let inputUnits = UInt64(value) else {
            throw ValidationError.invalidUnits
        }

        guard inputUnits > 0 else {
            throw ValidationError.zeroUnits
        }

        guard let available = UInt64(availableUnits) else {
            throw ValidationError.invalidUnits
        }

        guard inputUnits <= available else {
            throw ValidationError.exceedsAvailable(available: availableUnits)
        }
    }
}
