//
//  SwapError.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 16.07.2024.
//

import Foundation

enum SwapError: Error, LocalizedError {
    case routeUnavailable
    case noLiquidityPool
    case swapAmountTooSmall
    case lessThenMinSwapAmount(amount: String)
    case serverError(message: String)

    var errorDescription: String? {
        switch self {
        case .routeUnavailable:
            return "swapRouteNotAvailable".localized
        case .noLiquidityPool:
            return "noLiquidityPool".localized
        case .swapAmountTooSmall:
            return "swapAmountTooSmall".localized
        case .lessThenMinSwapAmount(let amount):
            return String(format: "swapAmountTooSmallRecommended".localized, amount)
        case .serverError(let msg):
            return msg
        }
    }
}
