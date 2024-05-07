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
    @Published var quote: SwapQuote?

    var fromBalance: String {
        return fromCoin.balanceString
    }

    var toBalance: String {
        return toCoin.balanceString
    }

    var toAmount: String {
        guard let amount = quote?.toAmount else {
            return .zero
        }
        return amount.description
    }

    var router: String? {
        return quote?.router
    }

    var inboundFee: BigInt? {
        return quote?.inboundFee(toCoin: toCoin)
    }
}

extension SwapTransaction {
    
    var amountDecimal: Decimal {
        let amountString = fromAmount.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: amountString) ?? .zero
    }
    
    var amountInCoinDecimal: BigInt {
        return fromCoin.raw(for: amountDecimal)
    }
}
