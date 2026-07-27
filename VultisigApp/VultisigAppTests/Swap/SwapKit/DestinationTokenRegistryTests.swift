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

    // MARK: - catalog(for:) merge / precedence / verification

    func testCatalogDedupsByUniqueIdAcrossProviders() async {
        let registry = TokenCatalogRepository()
        let a = CatalogFakeProvider(kind: "a", precedence: 0, tokens: [
            .ethereum: [Self.catalog(ticker: "USDC", contract: "0xUSDC", verification: .unverified, kind: "a")]
        ])
        let b = CatalogFakeProvider(kind: "b", precedence: 0, tokens: [
            .ethereum: [Self.catalog(ticker: "usdc", contract: "0xusdc", verification: .unverified, kind: "b")]
        ])
        registry.register(a)
        registry.register(b)

        let catalog = await registry.catalog(for: .ethereum)
        XCTAssertEqual(catalog.count, 1, "Same uniqueId (case-insensitive) collapses to one entry")
        XCTAssertEqual(catalog.first?.uniqueId, Self.coin(ticker: "USDC", contract: "0xUSDC").uniqueId)
    }

    func testCatalogHigherPrecedenceMetaWins() async {
        let registry = TokenCatalogRepository()
        // Low-precedence provider seen first, with an empty logo.
        let dynamic = CatalogFakeProvider(kind: "dynamic", precedence: 0, tokens: [
            .ethereum: [CatalogToken(
                meta: CoinMeta(chain: .ethereum, ticker: "USDC", logo: "", decimals: 6,
                               priceProviderId: "", contractAddress: "0xabc", isNativeToken: false),
                verification: .verified(source: "CoinGecko"), sourceKind: "dynamic")]
        ])
        // High-precedence curated provider with the good logo + priceProviderId.
        let curated = CatalogFakeProvider(kind: "curated", precedence: Int.max, tokens: [
            .ethereum: [CatalogToken(
                meta: CoinMeta(chain: .ethereum, ticker: "USDC", logo: "usdc-logo", decimals: 6,
                               priceProviderId: "usd-coin", contractAddress: "0xABC", isNativeToken: false),
                verification: .curated, sourceKind: "curated")]
        ])
        registry.register(dynamic)
        registry.register(curated)

        let catalog = await registry.catalog(for: .ethereum)
        XCTAssertEqual(catalog.count, 1)
        XCTAssertEqual(catalog.first?.meta.logo, "usdc-logo", "Curated (higher precedence) CoinMeta wins the logo")
        XCTAssertEqual(catalog.first?.meta.priceProviderId, "usd-coin", "Curated priceProviderId survives")
        XCTAssertEqual(catalog.first?.verification, .curated, "Strongest verification kept")
    }

    func testCatalogKeepsStrongestVerificationWhenLowPrecedenceIsMoreTrusted() async {
        let registry = TokenCatalogRepository()
        // High-precedence but unverified (e.g. a raw dynamic list winning the meta).
        let highUnverified = CatalogFakeProvider(kind: "high", precedence: 10, tokens: [
            .ethereum: [Self.catalog(ticker: "USDC", contract: "0xabc", verification: .unverified, kind: "high")]
        ])
        // Low-precedence but verified.
        let lowVerified = CatalogFakeProvider(kind: "low", precedence: 0, tokens: [
            .ethereum: [Self.catalog(ticker: "USDC", contract: "0xabc", verification: .verified(source: "CoinGecko"), kind: "low")]
        ])
        registry.register(highUnverified)
        registry.register(lowVerified)

        let catalog = await registry.catalog(for: .ethereum)
        XCTAssertEqual(catalog.count, 1)
        XCTAssertEqual(catalog.first?.sourceKind, "high", "Higher-precedence provider still supplies the CoinMeta")
        XCTAssertEqual(catalog.first?.verification, .verified(source: "CoinGecko"),
                       "Strongest verification is kept even from a lower-precedence provider")
    }

    func testCatalogPreservesFirstSeenOrder() async {
        let registry = TokenCatalogRepository()
        let provider = CatalogFakeProvider(kind: "p", precedence: 0, tokens: [
            .ethereum: [
                Self.catalog(ticker: "AAA", contract: "0x1", verification: .verified(source: "s"), kind: "p"),
                Self.catalog(ticker: "BBB", contract: "0x2", verification: .verified(source: "s"), kind: "p"),
                Self.catalog(ticker: "CCC", contract: "0x3", verification: .verified(source: "s"), kind: "p")
            ]
        ])
        registry.register(provider)

        let catalog = await registry.catalog(for: .ethereum)
        XCTAssertEqual(catalog.map { $0.meta.ticker }, ["AAA", "BBB", "CCC"])
    }

    // MARK: - Fixtures

    private static func catalog(ticker: String, contract: String, verification: TokenVerification, kind: String) -> CatalogToken {
        CatalogToken(meta: coin(ticker: ticker, contract: contract), verification: verification, sourceKind: kind)
    }

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
    let kind: String
    let buckets: [Chain: DestinationTokenBucket]

    init(kind: String, buckets: [Chain: DestinationTokenBucket]) {
        self.kind = kind
        self.buckets = buckets
    }

    func tokens(for chain: Chain, forceRefresh _: Bool) async -> DestinationTokenBucket {
        buckets[chain] ?? .empty(chain: chain)
    }
}

/// Provider that emits explicit `CatalogToken`s (with per-token verification +
/// a provider-level precedence), for exercising `catalog(for:)`'s merge rules.
@MainActor
private final class CatalogFakeProvider: TokenCatalogProvider {
    let kind: String
    let precedence: Int
    private let tokensByChain: [Chain: [CatalogToken]]

    init(kind: String, precedence: Int, tokens: [Chain: [CatalogToken]]) {
        self.kind = kind
        self.precedence = precedence
        self.tokensByChain = tokens
    }

    // Unused by catalog() (which calls catalogTokens); satisfies the protocol.
    // swiftlint:disable:next async_without_await
    func tokens(for chain: Chain, forceRefresh _: Bool) async -> DestinationTokenBucket {
        let metas = (tokensByChain[chain] ?? []).map(\.meta)
        return DestinationTokenBucket(chain: chain, tokens: metas, uniqueIds: Set(metas.map(\.uniqueId)))
    }

    // swiftlint:disable:next async_without_await
    func catalogTokens(for chain: Chain, forceRefresh _: Bool) async -> [CatalogToken] {
        tokensByChain[chain] ?? []
    }
}
