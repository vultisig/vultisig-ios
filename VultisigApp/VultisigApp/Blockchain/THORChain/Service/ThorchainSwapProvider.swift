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

    /// Wraps a fetched native quote in the `SwapQuote` case that identifies this
    /// service's network. The concrete service type is the only thing that
    /// carries the THORChain network (mainnet vs chainnet vs stagenet) — the
    /// coarser `SwapProvider` has no such distinction — so each conformer
    /// declares its own tag here. Making this a protocol requirement means a
    /// newly added service fails to compile until it maps itself, which is what
    /// prevents a silent mislabel.
    func makeSwapQuote(_ quote: ThorchainSwapQuote) -> SwapQuote
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
