//
//  KyberSwapPayload.swift
//  VultisigApp
//
//  Created by AI Assistant on [Current Date].
//

import Foundation
import BigInt

struct KyberSwapPayload: Codable, Hashable {
    let fromCoin: Coin
    let toCoin: Coin
    let fromAmount: BigInt
    let toAmountDecimal: Decimal
    let quote: KyberSwapQuote
} 