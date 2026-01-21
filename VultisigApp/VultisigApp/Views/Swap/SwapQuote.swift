//
//  SwapQuote.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 08.05.2024.
//

import Foundation
import BigInt

enum SwapQuote {
    case thorchain(ThorchainSwapQuote)
    case thorchainStagenet(ThorchainSwapQuote)
    case mayachain(ThorchainSwapQuote)
    case oneinch(EVMQuote, fee: BigInt?)
    case kyberswap(EVMQuote, fee: BigInt?)
    case lifi(EVMQuote, fee: BigInt?, integratorFee: Decimal?)

    var swapProviderId: SwapProviderId? {
        switch self {
        case .thorchain, .thorchainStagenet, .mayachain:
            return nil
        case .oneinch:
            return .oneInch
        case .kyberswap:
            return .kyberSwap
        case .lifi:
            return .lifi
        }
    }

    var router: String? {
        switch self {
        case .thorchain(let quote), .thorchainStagenet(let quote), .mayachain(let quote):
            return quote.router
        case .oneinch(let quote, _),
                .lifi(let quote, _, _),
                .kyberswap(let quote, _):
            return quote.tx.to
        }
    }

    var totalSwapSeconds: Int? {
        switch self {
        case .thorchain(let quote), .thorchainStagenet(let quote), .mayachain(let quote):
            return quote.totalSwapSeconds
        case .oneinch, .kyberswap, .lifi:
            return nil
        }
    }

    var inboundAddress: String? {
        switch self {
        case .thorchain(let quote), .thorchainStagenet(let quote), .mayachain(let quote):
            return quote.inboundAddress
        case .oneinch(let quote, _),
                .lifi(let quote, _, _),
                .kyberswap(let quote, _):
            return quote.tx.to
        }
    }

    var displayName: String? {
        switch self {
        case .thorchain:
            return "THORChain"
        case .thorchainStagenet:
            return "THORChain-Stagenet"
        case .mayachain:
            return "Maya protocol"
        case .oneinch:
            return "1Inch"
        case .kyberswap:
            return "KyberSwap"
        case .lifi:
            return "LI.FI"
        }
    }

    func inboundFeeDecimal(toCoin: Coin) -> Decimal? {
        switch self {
        case .thorchain(let quote), .thorchainStagenet(let quote), .mayachain(let quote):
            guard let fees = Decimal(string: quote.fees.total) else { return nil }
            return fees / toCoin.thorswapMultiplier
        case .lifi(let quote, _, let integratorFee):
            // Li.Fi charges integrator fee on the output amount
            let toAmountBigInt = BigInt(quote.dstAmount) ?? .zero
            let toAmountDecimal = toCoin.decimal(for: toAmountBigInt)
            return toAmountDecimal * (integratorFee ?? 0)
        case .oneinch, .kyberswap:
            return .zero
        }
    }

    var memo: String? {
        switch self {
        case .thorchain(let quote), .thorchainStagenet(let quote), .mayachain(let quote):
            return quote.memo
        case .oneinch, .kyberswap, .lifi:
            return nil
        }
    }
    var hashValue: Int {
        switch self {
        case .thorchain(let quote):
            return quote.hashValue
        case .thorchainStagenet(let quote):
            return quote.hashValue
        case .mayachain(let quote):
            return quote.hashValue
        case .oneinch(let quote, let fee):
            return quote.hashValue ^ fee.hashValue
        case .kyberswap(let quote, let fee):
            return quote.hashValue ^ fee.hashValue
        case .lifi(let quote, let fee, _):
            return quote.hashValue ^ fee.hashValue
        }
    }
}
