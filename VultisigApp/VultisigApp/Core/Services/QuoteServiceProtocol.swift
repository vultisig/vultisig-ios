//
//  QuoteServiceProtocol.swift
//  VultisigApp
//
//  Test seam over `SwapService`'s quote fetch. Mirrors today's call signature
//  in `SwapCryptoLogic.fetchQuote` so the §2 `SwapInteractor` can swap a mock
//  in for unit tests without touching the live aggregator pool.
//

import Foundation

protocol QuoteServiceProtocol {
    func fetchQuote(
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        isAffiliate: Bool,
        referredCode: String,
        vultTierDiscount: Int
    ) async throws -> SwapQuote

    /// Same fan-out as `fetchQuote`, but returns the full ranked candidate set
    /// alongside the auto-selected winner so the provider-selection UI can offer
    /// alternatives without a second fetch.
    func fetchQuotes(
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        isAffiliate: Bool,
        referredCode: String,
        vultTierDiscount: Int,
        slippageBps: Int?
    ) async throws -> SwapQuotes
}

extension SwapService: QuoteServiceProtocol {}
