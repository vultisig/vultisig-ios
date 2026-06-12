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

    /// Coin context for `quote.tx.swapFee`. The amount alone is ambiguous
    /// because providers denominate the affiliate fee in different coins
    /// (KyberSwap charges it in the destination token; LiFi declares the
    /// fee token on the quote). nil means unknown (legacy sender) — the
    /// co-signer renders no fee row rather than guessing a coin.
    var swapFeeChain: String? = nil
    var swapFeeTokenId: String? = nil
    var swapFeeDecimals: Int? = nil
}
