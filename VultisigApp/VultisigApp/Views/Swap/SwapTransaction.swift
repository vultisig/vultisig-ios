//
//  SwapCryptoTransaction.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 08.04.2024.
//

import Foundation
import BigInt

@MainActor
class SwapTransaction: ObservableObject {

    @Published var fromCoin: Coin = .example
    @Published var toCoin: Coin = .example
    @Published var fromAmount: String = .empty
    @Published var thorchainFee: BigInt = .zero
    @Published var oneInchFee: BigInt = .zero
    @Published var gas: BigInt = .zero
    @Published var quote: SwapQuote?

    var fee: BigInt {
        switch quote {
        case .thorchain, .mayachain:
            return thorchainFee
        case .oneinch:
            return oneInchFee
        case nil:
            return .zero
        }
    }

    var fromBalance: String {
        return fromCoin.balanceString
    }

    var toBalance: String {
        return toCoin.balanceString
    }

    var toAmountDecimal: Decimal {
        guard let quote else {
            return .zero
        }
        switch quote {
        case .mayachain(let quote), .thorchain(let quote):
            let expected = Decimal(string: quote.expectedAmountOut) ?? 0
            return expected / toCoin.thorswapMultiplier
        case .oneinch(let quote):
            let amount = BigInt(quote.dstAmount) ?? BigInt.zero
            return toCoin.decimal(for: amount)
        }
    }

    var toAmountRaw: BigInt {
        guard let quote else {
            return .zero
        }
        switch quote {
        case .thorchain, .mayachain:
            return toCoin.raw(for: toAmountDecimal)
        case .oneinch(let quote):
            return BigInt(quote.dstAmount) ?? BigInt.zero
        }
    }

    var router: String? {
        return quote?.router
    }

    var inboundFeeDecimal: Decimal? {
        return quote?.inboundFeeDecimal(toCoin: toCoin)
    }
}

extension SwapTransaction {
    
    var fromAmountDecimal: Decimal {
        let amountString = fromAmount.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: amountString) ?? .zero
    }

    var amountInCoinDecimal: BigInt {
        return fromCoin.raw(for: fromAmountDecimal)
    }
}
