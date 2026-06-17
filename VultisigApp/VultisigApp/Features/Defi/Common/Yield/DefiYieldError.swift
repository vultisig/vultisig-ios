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
    /// A provider was asked to build a payload it doesn't support (e.g. cancel on
    /// Circle/Noon, which have no `cancelUnstake`).
    case unsupportedOperation

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "invalidAmount".localized
        case .unsupportedOperation:
            return "defiUnsupportedOperation".localized
        }
    }
}
