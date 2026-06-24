//
//  SwapKitTokensCacheTests.swift
//  VultisigAppTests
//
//  Freshness behaviour for the SwapKit destination-token catalog cache.
//  Covers the `forceRefresh` path the destination picker uses on its first
//  open per presentation: it bypasses the TTL-fresh early-return, still
//  coalesces concurrent callers onto one in-flight fetch, and still serves
//  the last-good snapshot when a forced fetch fails.
//

import XCTest
@testable import VultisigApp

@MainActor
final class SwapKitTokensCacheTests: XCTestCase {

    // MARK: - forceRefresh bypasses fresh TTL

    /// A fresh snapshot (within `tokensCacheTTL`) is normally served without a
    /// network hit. `forceRefresh: true` must skip that early-return and issue
    /// a new fetch even though the snapshot is fresh.
    func testForceRefresh_bypassesFreshTTL_refetches() async {
        let client = StubHTTPClient()
        let cache = SwapKitTokensCache(httpClient: client, providerCache: makeProviderCache(client))
        let now = Date()

        // Warm the cache (one fetch fans out to one provider → one /tokens call).
        _ = await cache.tokens(for: .ethereum, forceRefresh: false, now: now)
        XCTAssertEqual(client.tokensCallCount, 1)

        // A fresh, non-forced read must NOT refetch.
        _ = await cache.tokens(for: .ethereum, forceRefresh: false, now: now)
        XCTAssertEqual(client.tokensCallCount, 1, "Fresh snapshot must be served without a refetch")

        // A forced read on the still-fresh snapshot must refetch.
        _ = await cache.tokens(for: .ethereum, forceRefresh: true, now: now)
        XCTAssertEqual(client.tokensCallCount, 2, "forceRefresh must bypass fresh-TTL early-return")
    }

    // MARK: - forceRefresh coalesces concurrent callers

    /// Concurrent forced reads must share a single in-flight fetch rather than
    /// stampeding the proxy with one /tokens call each.
    func testForceRefresh_coalescesConcurrentCalls() async {
        let client = StubHTTPClient()
        client.artificialDelay = true
        let cache = SwapKitTokensCache(httpClient: client, providerCache: makeProviderCache(client))
        let now = Date()

        async let a = cache.tokens(for: .ethereum, forceRefresh: true, now: now)
        async let b = cache.tokens(for: .ethereum, forceRefresh: true, now: now)
        async let c = cache.tokens(for: .ethereum, forceRefresh: true, now: now)
        let results = await [a, b, c]

        XCTAssertEqual(client.tokensCallCount, 1, "Concurrent forced reads must coalesce onto one fetch")
        for bucket in results {
            XCTAssertEqual(bucket.tokens.first?.ticker, "USDC")
        }
    }

    // MARK: - forceRefresh serves last-good on failure

    /// A forced read whose fetch fails entirely (no provider snapshot to fan
    /// out against) must keep serving the prior snapshot rather than collapsing
    /// to an empty bucket. Seed a known-good snapshot, then force a refresh
    /// through a failing client whose provider cache has no snapshot — the
    /// fan-out short-circuits to `nil` and the cache falls back to last-good.
    func testForceRefresh_servesLastGoodWhenFetchFails() async {
        let usdc = CoinMeta(
            chain: .ethereum,
            ticker: "USDC",
            logo: "",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            isNativeToken: false
        )
        let bucket = DestinationTokenBucket(
            chain: .ethereum,
            tokens: [usdc],
            uniqueIds: [usdc.uniqueId]
        )

        let failingClient = StubHTTPClient()
        failingClient.failAll = true
        let cache = SwapKitTokensCache(
            httpClient: failingClient,
            providerCache: SwapKitProviderCache(httpClient: failingClient)
        )
        cache.setSnapshot(buckets: [.ethereum: bucket], fetchedAt: Date(timeIntervalSince1970: 0))

        // Force a refresh well past the TTL — the snapshot is stale, the fetch
        // fails (no provider snapshot), so last-good must be served.
        let degraded = await cache.tokens(for: .ethereum, forceRefresh: true, now: Date())
        XCTAssertEqual(degraded.tokens.first?.ticker, "USDC", "Failed forced fetch must serve last-good snapshot")
    }

    // MARK: - Helpers

    /// A provider cache that resolves through the same stub client so the
    /// tokens cache fans out against a known single-provider snapshot.
    private func makeProviderCache(_ client: StubHTTPClient) -> SwapKitProviderCache {
        SwapKitProviderCache(httpClient: client)
    }
}

// MARK: - Test double

/// Stub `HTTPClientProtocol` that answers `/providers` with one ETH-enabled
/// provider and `/tokens` with a single ETH USDC entry. Counts `/tokens`
/// hits (for coalescing assertions) and can be flipped to fail every request.
@MainActor
private final class StubHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private enum StubError: Error { case unavailable }

    var failAll = false
    var artificialDelay = false
    private(set) var tokensCallCount = 0

    private static let providersJSON = """
    [
      {
        "name": "PROVIDER_X",
        "provider": "PROVIDER_X",
        "displayName": "Provider X",
        "displayNameLong": "Provider X Long",
        "count": 1,
        "enabledChainIds": ["1"],
        "supportedChainIds": ["1"],
        "supportedActions": ["swap"]
      }
    ]
    """

    private static let tokensJSON = """
    {
      "provider": "PROVIDER_X",
      "count": 1,
      "tokens": [
        {
          "chain": "ETH",
          "chainId": "1",
          "address": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
          "ticker": "USDC",
          "identifier": "ETH.USDC-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
          "name": "USD Coin",
          "decimals": 6,
          "logoURI": null,
          "coingeckoId": "usd-coin"
        }
      ]
    }
    """

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        if artificialDelay {
            // Hold the in-flight fetch open long enough for concurrent callers
            // to coalesce onto it before it resolves.
            try? await Task.sleep(nanoseconds: 20_000_000)
        } else {
            await Task.yield()
        }

        if failAll {
            throw StubError.unavailable
        }

        let path = target.path
        if path == "/providers" {
            return HTTPResponse(data: Data(Self.providersJSON.utf8), response: Self.ok)
        }
        if path == "/tokens" {
            tokensCallCount += 1
            return HTTPResponse(data: Data(Self.tokensJSON.utf8), response: Self.ok)
        }
        throw StubError.unavailable
    }

    private static let ok = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
}
