//
//  DestinationTokenRegistryTests.swift
//  VultisigAppTests
//
//  Registry coverage for `DestinationTokenRegistry` — the aggregator the
//  swap coin picker uses to pull destination tokens from every
//  registered `DestinationTokenProvider`. Tests use the exposed
//  test-only initialiser so cases don't depend on the order in which
//  app-startup registrations land in `DestinationTokenRegistry.shared`.
//

import XCTest
@testable import VultisigApp

@MainActor
final class DestinationTokenRegistryTests: XCTestCase {

    func testRegisterAndLookup() async {
        let registry = DestinationTokenRegistry()
        let swapKit = FakeProvider(kind: "swapKit", buckets: [
            .ethereum: DestinationTokenBucket(
                chain: .ethereum,
                tokens: [Self.coin(ticker: "SKT", contract: "0xaaa")],
                uniqueIds: [Self.coin(ticker: "SKT", contract: "0xaaa").uniqueId]
            )
        ])
        let chainflip = FakeProvider(kind: "chainflip", buckets: [
            .ethereum: DestinationTokenBucket(
                chain: .ethereum,
                tokens: [Self.coin(ticker: "CFP", contract: "0xbbb")],
                uniqueIds: [Self.coin(ticker: "CFP", contract: "0xbbb").uniqueId]
            )
        ])

        registry.register(swapKit)
        registry.register(chainflip)

        let buckets = await registry.tokens(for: .ethereum)

        XCTAssertEqual(buckets.count, 2, "Both providers must contribute a bucket")
        let tickers = buckets.flatMap { $0.tokens.map(\.ticker) }
        XCTAssertEqual(Set(tickers), ["SKT", "CFP"])
    }

    func testReRegisterOverwrites() async {
        let registry = DestinationTokenRegistry()
        let first = FakeProvider(kind: "swapKit", buckets: [
            .ethereum: DestinationTokenBucket(
                chain: .ethereum,
                tokens: [Self.coin(ticker: "OLD", contract: "0xaaa")],
                uniqueIds: [Self.coin(ticker: "OLD", contract: "0xaaa").uniqueId]
            )
        ])
        let second = FakeProvider(kind: "swapKit", buckets: [
            .ethereum: DestinationTokenBucket(
                chain: .ethereum,
                tokens: [Self.coin(ticker: "NEW", contract: "0xbbb")],
                uniqueIds: [Self.coin(ticker: "NEW", contract: "0xbbb").uniqueId]
            )
        ])

        registry.register(first)
        registry.register(second)

        XCTAssertEqual(registry.registeredCountForTesting, 1,
                       "Re-registering the same providerKind must overwrite, not duplicate")

        let buckets = await registry.tokens(for: .ethereum)
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets.first?.tokens.map(\.ticker), ["NEW"],
                       "Latest registration wins on the same providerKind")
    }

    func testEmptyRegistryReturnsEmptyArray() async {
        let registry = DestinationTokenRegistry()

        let buckets = await registry.tokens(for: .ethereum)

        XCTAssertTrue(buckets.isEmpty,
                      "Registry with no providers must produce no buckets")
    }

    func testProviderReturningEmptyBucketDoesNotBreakAggregation() async {
        let registry = DestinationTokenRegistry()
        let dormant = FakeProvider(kind: "swapKit", buckets: [:])
        let live = FakeProvider(kind: "chainflip", buckets: [
            .ethereum: DestinationTokenBucket(
                chain: .ethereum,
                tokens: [Self.coin(ticker: "CFP", contract: "0xbbb")],
                uniqueIds: [Self.coin(ticker: "CFP", contract: "0xbbb").uniqueId]
            )
        ])

        registry.register(dormant)
        registry.register(live)

        let buckets = await registry.tokens(for: .ethereum)

        XCTAssertEqual(buckets.count, 2, "Empty buckets still surface — picker dedups, not the registry")
        XCTAssertEqual(buckets.first?.tokens, [],
                       "Dormant provider's bucket must be empty (insertion order preserved)")
        XCTAssertEqual(buckets.last?.tokens.map(\.ticker), ["CFP"])
    }

    // MARK: - Fixtures

    private static func coin(ticker: String, contract: String) -> CoinMeta {
        CoinMeta(
            chain: .ethereum,
            ticker: ticker,
            logo: "",
            decimals: 18,
            priceProviderId: "",
            contractAddress: contract,
            isNativeToken: false
        )
    }
}

// MARK: - Fakes

/// Configurable provider for registry tests. Each instance pins its own
/// `providerKind` so multiple kinds can coexist in a single test case
/// (mirrors how the production `DestinationTokenProvider` conformers like
/// `SwapKitTokensCache` expose `providerKind` as an instance property,
/// unlike `SwapTrackingService`'s static dispatch).
@MainActor
private final class FakeProvider: DestinationTokenProvider {
    let providerKind: String
    let buckets: [Chain: DestinationTokenBucket]

    init(kind: String, buckets: [Chain: DestinationTokenBucket]) {
        self.providerKind = kind
        self.buckets = buckets
    }

    func tokens(for chain: Chain) async -> DestinationTokenBucket {
        buckets[chain] ?? .empty(chain: chain)
    }
}
