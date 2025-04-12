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
    case serverError(message: String)

    var errorDescription: String? {
        switch self {
        case .routeUnavailable:
            return "Bridge route not available"
        case .swapAmountTooSmall:
            return "Bridge amount too small"
        case .lessThenMinSwapAmount(let amount):
            return "Bridge amount too small. Recommended amount \(amount)"
        case .serverError(let msg):
            return msg
        }
    }
}
