//
//  DefiYieldError.swift
//  VultisigApp
//

import Foundation

/// Errors surfaced by the shared yield-vault forms to the user.
enum DefiYieldError: Error, LocalizedError {
    /// The entered amount could not be converted to integer base units, so the
    /// request was blocked rather than building a zero-amount transaction.
    case invalidAmount

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "invalidAmount".localized
        }
    }
}
