//
//  SwapError.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 16.07.2024.
//

import Foundation

enum SwapError: Error, LocalizedError, Equatable {
    case routeUnavailable
    case recipientRouteUnavailable
    /// The built swap artifact does not target the intended external recipient
    /// (the provider dropped/misused the recipient param). Raised by
    /// `SwapRecipientVerifier` before signing so funds are never misdirected.
    case recipientVerificationFailed
    case noLiquidityPool
    case tradingHalted
    case swapAmountTooSmall
    /// The node refused the quote because its simulated output fell below the
    /// minimum-output floor derived from the requested slippage tolerance.
    /// Actionable by the user: raise the slippage setting or reduce the amount.
    case slippageToleranceTooTight
    case lessThenMinSwapAmount(amount: String)
    case serverError(message: String)

    var errorDescription: String? {
        switch self {
        case .routeUnavailable:
            return "swapRouteNotAvailable".localized
        case .recipientRouteUnavailable:
            return "swapRecipientRouteNotAvailable".localized
        case .recipientVerificationFailed:
            return "swapRecipientVerificationFailed".localized
        case .noLiquidityPool:
            return "noLiquidityPool".localized
        case .tradingHalted:
            return "swapTradingHalted".localized
        case .swapAmountTooSmall:
            return "swapAmountTooSmall".localized
        case .slippageToleranceTooTight:
            return "swapSlippageToleranceTooTight".localized
        case .lessThenMinSwapAmount(let amount):
            return String(format: "swapAmountTooSmallRecommended".localized, amount)
        case .serverError(let msg):
            return msg
        }
    }
}
