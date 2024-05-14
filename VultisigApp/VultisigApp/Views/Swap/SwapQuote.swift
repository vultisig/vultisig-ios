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

    func inboundFee(toCoin: Coin) -> BigInt? {
        switch self {
        case .thorchain(let quote):
            guard let fees = Decimal(string: quote.fees.total) else {
                return nil
            }
            let toDecimals = Int(toCoin.decimals) ?? 0
            let powerBy = toDecimals - 8
            let inboundFeeDecimal: Decimal

            if powerBy >= 0 {
                inboundFeeDecimal = fees * pow(10, abs(powerBy))
            } else {
                inboundFeeDecimal = fees / pow(10, abs(powerBy))
            }

            return BigInt(stringLiteral: inboundFeeDecimal.description)

        case .oneinch:
            return .zero
        }
    }
}
