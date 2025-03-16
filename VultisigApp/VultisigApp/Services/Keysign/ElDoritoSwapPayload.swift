//
//  OneInchSwapPayload.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 11.05.2024.
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
