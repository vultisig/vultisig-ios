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
    case mayachain(THORChainSwapPayload)
    case oneInch(OneInchSwapPayload)
    case kyberSwap(KyberSwapPayload)

    var fromCoin: Coin {
        switch self {
        case .thorchain(let payload), .mayachain(let payload):
            return payload.fromCoin
        case .oneInch(let payload):
            return payload.fromCoin
        case .kyberSwap(let payload):
            return payload.fromCoin
        }
    }

    var toCoin: Coin {
        switch self {
        case .thorchain(let payload), .mayachain(let payload):
            return payload.toCoin
        case .oneInch(let payload):
            return payload.toCoin
        case .kyberSwap(let payload):
            return payload.toCoin
        }
    }

    var fromAmount: BigInt {
        switch self {
        case .thorchain(let payload), .mayachain(let payload):
            return payload.fromAmount
        case .oneInch(let payload):
            return payload.fromAmount
        case .kyberSwap(let payload):
            return payload.fromAmount
        }
    }

    var toAmountDecimal: Decimal {
        switch self {
        case .thorchain(let payload), .mayachain(let payload):
            return payload.toAmountDecimal
        case .oneInch(let payload):
            return payload.toAmountDecimal
        case .kyberSwap(let payload):
            return payload.toAmountDecimal
        }
    }

    var router: String? {
        switch self {
        case .thorchain(let payload), .mayachain(let payload):
            return payload.routerAddress
        case .oneInch(let payload):
            return payload.quote.tx.to
        case .kyberSwap(let payload):
            return payload.quote.tx.to
        }
    }

    var isDeposit: Bool {
        switch self {
        case .mayachain(let payload):
            return payload.fromCoin.chain == .mayaChain && payload.toCoin.chain == .thorChain
        case .oneInch, .kyberSwap, .thorchain:
            return false
        }
    }
}
