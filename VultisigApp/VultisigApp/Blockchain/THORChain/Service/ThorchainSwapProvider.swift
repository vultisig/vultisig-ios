//
//  ThorchainSwapProvider.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 06.06.2024.
//

import Foundation

protocol ThorchainSwapProvider {
    func fetchSwapQuotes(
        address: String,
        fromAsset: String,
        toAsset: String,
        amount: String,
        interval: Int,
        streamingQuantity: Int,
        liquidityToleranceBps: Int,
        referredCode: String,
        vultTierDiscount: Int
    ) async throws -> ThorchainSwapQuote
}

extension ThorchainSwapProvider {
    func fetchSwapQuotes(
        address: String,
        fromAsset: String,
        toAsset: String,
        amount: String,
        interval: Int,
        liquidityToleranceBps: Int,
        referredCode: String,
        vultTierDiscount: Int
    ) async throws -> ThorchainSwapQuote {
        try await fetchSwapQuotes(
            address: address,
            fromAsset: fromAsset,
            toAsset: toAsset,
            amount: amount,
            interval: interval,
            streamingQuantity: 0,
            liquidityToleranceBps: liquidityToleranceBps,
            referredCode: referredCode,
            vultTierDiscount: vultTierDiscount
        )
    }
}
