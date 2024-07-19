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
    case oneinch(OneInchQuote)
    case lifi(OneInchQuote)

    var router: String? {
        switch self {
        case .thorchain(let quote), .mayachain(let quote):
            return quote.router
        case .oneinch(let quote), .lifi(let quote):
            return quote.tx.to
        }
    }

    var totalSwapSeconds: Int? {
        switch self {
        case .thorchain(let quote), .mayachain(let quote):
            return quote.totalSwapSeconds
        case .oneinch, .lifi:
            return nil
        }
    }

    var inboundAddress: String? {
        switch self {
        case .thorchain(let quote), .mayachain(let quote):
            return quote.inboundAddress
        case .oneinch(let quote), .lifi(let quote):
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
        case .lifi:
            return "LI.FI"
        }
    }

    func inboundFeeDecimal(toCoin: Coin) -> Decimal? {
        switch self {
        case .thorchain(let quote), .mayachain(let quote):
            guard let fees = Decimal(string: quote.fees.total) else { return nil }
            return fees / toCoin.thorswapMultiplier
        case .oneinch, .lifi:
            return .zero
        }
    }

    var memo: String? {
        switch self {
        case .mayachain(let quote):
            return quote.memo
        case .thorchain, .oneinch, .lifi:
            return nil
        }
    }
}
