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
    /// Source amounts the VM probed with, in call order — lets tests assert the
    /// pre-input market probe is sized to a fiat notional rather than 1 unit.
    private(set) var marketPriceAmounts: [BigInt] = []

    /// Stubbed Advanced Swap Queue gate. Defaults to `false` (fail-closed) so a
    /// test must opt in to the "feature available" path explicitly.
    var advancedSwapQueueEnabledResult = false
    private(set) var advancedSwapQueueCallCount = 0

    var inboundAddressesResult: [InboundAddress] = []
    private(set) var inboundAddressesCallCount = 0

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
        marketPriceAmounts.append(sourceAmount)
        return try marketPriceResult.get()
    }

    func isAdvancedSwapQueueEnabled() async -> Bool {
        advancedSwapQueueCallCount += 1
        return advancedSwapQueueEnabledResult
    }

    func fetchInboundAddresses() async -> [InboundAddress] {
        inboundAddressesCallCount += 1
        return inboundAddressesResult
    }
}

// swiftlint:enable unused_parameter async_without_await
