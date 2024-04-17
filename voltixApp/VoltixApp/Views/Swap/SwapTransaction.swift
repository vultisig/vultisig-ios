//
//  SwapCryptoTransaction.swift
//  VoltixApp
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
    @Published var toAmount: String = .empty
    @Published var inboundFee: String = .empty
    @Published var gas: String = .empty
    @Published var duration: Int = .zero

    @Published var fromBalance: String = .zero
    @Published var toBalance: String = .zero
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
