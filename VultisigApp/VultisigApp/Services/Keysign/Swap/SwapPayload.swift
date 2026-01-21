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
    case thorchainStagenet(THORChainSwapPayload)
    case mayachain(THORChainSwapPayload)
    case generic(GenericSwapPayload)

    var fromCoin: Coin {
        switch self {
        case .thorchain(let payload), .thorchainStagenet(let payload), .mayachain(let payload):
            return payload.fromCoin
        case .generic(let payload):
            return payload.fromCoin
        }
    }

    var toCoin: Coin {
        switch self {
        case .thorchain(let payload), .thorchainStagenet(let payload), .mayachain(let payload):
            return payload.toCoin
        case .generic(let payload):
            return payload.toCoin
        }
    }

    var fromAmount: BigInt {
        switch self {
        case .thorchain(let payload), .thorchainStagenet(let payload), .mayachain(let payload):
            return payload.fromAmount
        case .generic(let payload):
            return payload.fromAmount
        }
    }

    var toAmountDecimal: Decimal {
        switch self {
        case .thorchain(let payload), .thorchainStagenet(let payload), .mayachain(let payload):
            return payload.toAmountDecimal
        case .generic(let payload):
            return payload.toAmountDecimal
        }
    }

    var router: String? {
        switch self {
        case .thorchain(let payload), .thorchainStagenet(let payload), .mayachain(let payload):
            return payload.routerAddress
        case .generic(let payload):
            return payload.quote.tx.to
        }
    }

    var isDeposit: Bool {
        switch self {
        case .mayachain(let payload):
            return payload.fromCoin.chain == .mayaChain && payload.toCoin.chain == .thorChain
        case .generic, .thorchain, .thorchainStagenet:
            return false
        }
    }

    var providerName: String {
        switch self {
        case .thorchain:
            return "THORChain"
        case .thorchainStagenet:
            return "THORChain-Stagenet"
        case .mayachain:
            return "Maya Protocol"
        case .generic(let payload):
            switch payload.provider {
            case .oneInch:
                return "1Inch"
            case .lifi:
                return "LI.FI"
            case .kyberSwap:
                return "KyberSwap"
            }
        }
    }
}
