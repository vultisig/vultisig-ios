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
    case oneinch(OneInchQuote)

    var router: String? {
        switch self {
        case .thorchain(let quote):
            return quote.router
        case .oneinch(let quote):
            return quote.tx.to
        }
    }

    var totalSwapSeconds: Int? {
        switch self {
        case .thorchain(let quote):
            return quote.totalSwapSeconds
        case .oneinch:
            return nil
        }
    }

    var inboundAddress: String? {
        switch self {
        case .thorchain(let quote):
            return quote.inboundAddress
        case .oneinch(let quote):
            return quote.tx.to
        }
    }
    
    var displayName: String? {
        switch self {
        case .thorchain(let quote):
            return "THORChain"
        case .oneinch(let quote):
            return "1Inch"
        }
    }

    func inboundFeeDecimal(toCoin: Coin) -> Decimal? {
        switch self {
        case .thorchain(let quote):
            guard let fees = Decimal(string: quote.fees.total) else {
                return nil
            }

            return fees / 1e8
        case .oneinch:
            return .zero
        }
    }
}
