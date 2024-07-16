//
//  SwapError.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 16.07.2024.
//

import Foundation

enum SwapError: Error, LocalizedError {
    case routeUnavailable
    case swapAmountTooSmall
    case lessThenMinSwapAmount(amount: String)

    var errorDescription: String? {
        switch self {
        case .routeUnavailable:
            return "Swap route not available"
        case .swapAmountTooSmall:
            return "Swap amount too small"
        case .lessThenMinSwapAmount(let amount):
            return "Swap amount too small. Recommended amount \(amount)"
        }
    }
}
