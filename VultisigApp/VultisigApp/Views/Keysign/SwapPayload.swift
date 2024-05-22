//
//  SwapPayload.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 10.05.2024.
//

import Foundation
import BigInt

enum SwapPayload: Codable, Hashable { // TODO: Merge with SwapQuote
    case thorchain(THORChainSwapPayload)
    case oneInch(OneInchSwapPayload)

    var fromCoin: Coin {
        switch self {
        case .thorchain(let payload):
            return payload.fromCoin
        case .oneInch(let payload):
            return payload.fromCoin
        }
    }

    var toCoin: Coin {
        switch self {
        case .thorchain(let payload):
            return payload.toCoin
        case .oneInch(let payload):
            return payload.toCoin
        }
    }

    var fromAmount: BigInt {
        switch self {
        case .thorchain(let payload):
            return payload.fromAmount
        case .oneInch(let payload):
            return payload.fromAmount
        }
    }

    var toAmountDecimal: Decimal {
        switch self {
        case .thorchain(let payload):
            return payload.toAmountDecimal
        case .oneInch(let payload):
            return payload.toAmountDecimal
        }
    }

    var router: String? {
        switch self {
        case .thorchain(let payload):
            return payload.routerAddress
        case .oneInch(let payload):
            return payload.quote.tx.to
        }
    }
}
