//
//  GenericSwapPayload.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 11.05.2024.
//

import Foundation
import BigInt

struct GenericSwapPayload: Codable, Hashable {
    let fromCoin: Coin
    let toCoin: Coin
    let fromAmount: BigInt
    let toAmountDecimal: Decimal
    let quote: EVMQuote
    let provider: SwapProviderId
}
