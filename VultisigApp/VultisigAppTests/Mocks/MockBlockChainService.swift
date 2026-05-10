//
//  MockBlockChainService.swift
//  VultisigAppTests
//

import Foundation
@testable import VultisigApp

// swiftlint:disable async_without_await

final class MockBlockChainService: BlockChainServiceProtocol, @unchecked Sendable {
    var stubbedResult: Result<BlockChainSpecific, Error>
    private(set) var fetchSwapCallCount = 0
    private(set) var lastFromCoin: Coin?
    private(set) var lastToCoin: Coin?
    private(set) var lastFromAmount: Decimal?
    private(set) var lastQuote: SwapQuote?

    init(stubbedResult: Result<BlockChainSpecific, Error>) {
        self.stubbedResult = stubbedResult
    }

    func fetchSwapBlockChainSpecific(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmount: Decimal,
        quote: SwapQuote?
    ) async throws -> BlockChainSpecific {
        fetchSwapCallCount += 1
        lastFromCoin = fromCoin
        lastToCoin = toCoin
        lastFromAmount = fromAmount
        lastQuote = quote
        return try stubbedResult.get()
    }
}

// swiftlint:enable async_without_await
