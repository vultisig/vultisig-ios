//
//  MockLimitSwapQuoteService.swift
//  VultisigAppTests
//

import BigInt
import Foundation
@testable import VultisigApp

// swiftlint:disable unused_parameter async_without_await

/// Test-only `LimitSwapQuoteServiceProtocol` double. Records call counts and
/// returns whatever `Result` the test configures. Pattern mirrors
/// `MockBlockaidRpcClient`.
final class MockLimitSwapQuoteService: LimitSwapQuoteServiceProtocol {

    enum StubError: Error {
        case notStubbed
    }

    var marketPriceResult: Result<Decimal, Error> = .failure(StubError.notStubbed)
    private(set) var marketPriceCallCount = 0
    private(set) var marketPriceQueries: [(sourceAsset: String, targetAsset: String)] = []

    func fetchCurrentMarketPrice(
        sourceAsset: String,
        sourceAmount: BigInt,
        sourceDecimals: Int,
        targetAsset: String,
        targetDecimals: Int,
        destinationAddress: String
    ) async throws -> Decimal {
        marketPriceCallCount += 1
        marketPriceQueries.append((sourceAsset, targetAsset))
        return try marketPriceResult.get()
    }
}

// swiftlint:enable unused_parameter async_without_await
