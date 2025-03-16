//
//  ElDoritoSwapPayload.swift
//  VoltixApp
//
//  Created by Enrique Souza
//

import Foundation
import BigInt

struct ElDoritoSwapPayload: Codable, Hashable {
    let fromCoin: Coin
    let toCoin: Coin
    let fromAmount: BigInt
    let toAmountDecimal: Decimal
    let quote: ElDoritoQuote
}
