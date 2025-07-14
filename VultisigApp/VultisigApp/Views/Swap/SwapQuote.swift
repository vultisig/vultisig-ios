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
    case mayachain(ThorchainSwapQuote)
    case oneinch(OneInchQuote, fee: BigInt?)
    case kyberswap(KyberSwapQuote, fee: BigInt?)
    case lifi(OneInchQuote, fee: BigInt?)

    var router: String? {
        switch self {
        case .thorchain(let quote), .mayachain(let quote):
            return quote.router
        case .oneinch(let quote, _), .lifi(let quote, _):
            return quote.tx.to
        case .kyberswap(let quote, _):
            return quote.tx.to
        }
    }

    var totalSwapSeconds: Int? {
        switch self {
        case .thorchain(let quote), .mayachain(let quote):
            return quote.totalSwapSeconds
        case .oneinch, .kyberswap, .lifi:
            return nil
        }
    }

    var inboundAddress: String? {
        switch self {
        case .thorchain(let quote), .mayachain(let quote):
            return quote.inboundAddress
        case .oneinch(let quote, _), .lifi(let quote, _):
            return quote.tx.to
        case .kyberswap(let quote, _):
            return quote.tx.to
        }
    }
    
    var displayName: String? {
        switch self {
        case .thorchain:
            return "THORChain"
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
        case .thorchain(let quote), .mayachain(let quote):
            guard let fees = Decimal(string: quote.fees.total) else { return nil }
            return fees / toCoin.thorswapMultiplier
        case .lifi(let quote, _):
            // Li.Fi charges integrator fee on the output amount
            let toAmountBigInt = BigInt(quote.dstAmount) ?? .zero
            let toAmountDecimal = toCoin.decimal(for: toAmountBigInt)
            return toAmountDecimal * LiFiService.integratorFeeDecimal
        case .oneinch, .kyberswap:
            return .zero
        }
    }

    var memo: String? {
        switch self {
        case .mayachain(let quote):
            return quote.memo
        case .thorchain, .oneinch, .kyberswap, .lifi:
            return nil
        }
    }
}
