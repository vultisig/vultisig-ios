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
    @Published var gas: BigInt = .zero
    @Published var quote: ThorchainSwapQuote?

    var fromBalance: String {
        return fromCoin.balanceString
    }

    var toBalance: String {
        return toCoin.balanceString
    }

    var toAmount: String {
        guard let quote, let expected = Decimal(string: quote.expectedAmountOut) else {
            return .zero
        }
        return (expected / Decimal(100_000_000)).description
    }

    var router: String? {
        return quote?.router
    }

    var inboundFee: BigInt? {
        guard let quote = quote, let fees = Decimal(string: quote.fees.total) else {
            return nil
        }
        let toDecimals = Int(toCoin.decimals) ?? 0
        let inboundFeeDecimal = fees * pow(10, max(0, toDecimals - 8))

        return BigInt(stringLiteral: inboundFeeDecimal.description)
    }
}

// TODO: Refactor amount conversions

extension SwapTransaction {

    var amountInWei: BigInt {
        BigInt(amountDecimal * pow(10, Double(EVMHelper.ethDecimals)))
    }

    var amountInTokenWei: BigInt {
        let decimals = Double(fromCoin.decimals) ?? Double(EVMHelper.ethDecimals) // The default is always in WEI unless the token has a different one like UDSC

        return BigInt(amountDecimal * pow(10, decimals))
    }

    var amountInLamports: Int64 {
        Int64(amountDecimal * 1_000_000_000)
    }

    var amountInSats: Int64 {
        Int64(amountDecimal * 100_000_000)
    }

    var amountDecimal: Double {
        let amountString = fromAmount.replacingOccurrences(of: ",", with: ".")
        return Double(amountString) ?? 0
    }
    var amountInCoinDecimal: Int64 {
        let amountDouble = amountDecimal
        let decimals = Int(fromCoin.decimals) ?? 8
        return Int64(amountDouble * pow(10,Double(decimals)))
    }
}
