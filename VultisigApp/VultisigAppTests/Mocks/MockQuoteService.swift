//
//  MockQuoteService.swift
//  VultisigAppTests
//

import Foundation
@testable import VultisigApp

// swiftlint:disable async_without_await unused_parameter

final class MockQuoteService: QuoteServiceProtocol {
    var stubbedResult: Result<SwapQuote, Error>
    private(set) var fetchQuoteCallCount = 0
    private(set) var lastVultTierDiscount: Int?

    init(stubbedResult: Result<SwapQuote, Error>) {
        self.stubbedResult = stubbedResult
    }

    func fetchQuote(
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        isAffiliate: Bool,
        referredCode: String,
        vultTierDiscount: Int
    ) async throws -> SwapQuote {
        fetchQuoteCallCount += 1
        lastVultTierDiscount = vultTierDiscount
        return try stubbedResult.get()
    }

    func fetchQuotes(
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        isAffiliate: Bool,
        referredCode: String,
        vultTierDiscount: Int,
        thorPools: [NativePoolAsset]?,
        mayaPools: [NativePoolAsset]?
    ) async throws -> SwapQuotes {
        fetchQuoteCallCount += 1
        lastVultTierDiscount = vultTierDiscount
        let best = try stubbedResult.get()
        return SwapQuotes(best: best, ranked: [best])
    }
}

// swiftlint:enable async_without_await unused_parameter
