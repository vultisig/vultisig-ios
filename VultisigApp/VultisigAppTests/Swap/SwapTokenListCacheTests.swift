//
//  SwapTokenListCacheTests.swift
//  VultisigAppTests
//
//  Covers the swap "Select asset" per-chain token list cache: hit-within-TTL
//  serves stored tokens without invoking the fetch closure, past-TTL refetches
//  and updates, per-chain isolation, fail-open to last-good on fetch error,
//  and in-flight coalescing (concurrent calls → one fetch). Uses `setCached`
//  + an injected `now` (mirrors `SwapKitProviderCacheTests`).
//

import XCTest
@testable import VultisigApp

@MainActor
final class SwapTokenListCacheTests: XCTestCase {

    private let ttl: TimeInterval = 6 * 60 * 60

    private func makeToken(_ ticker: String, chain: Chain = .ethereum) -> CoinMeta {
        CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: ticker.lowercased(),
            decimals: 18,
            priceProviderId: ticker.lowercased(),
            contractAddress: "0x\(ticker.lowercased())",
            isNativeToken: false
        )
    }

    private struct FetchError: Error {}

    // (a) Hit within TTL returns stored tokens WITHOUT invoking the fetch.
    func testHitWithinTTLReturnsStoredTokensWithoutFetching() async throws {
        let cache = SwapTokenListCache(ttl: ttl)
        let stored = [makeToken("USDC")]
        let now = Date()
        cache.setCached(stored, for: .ethereum, fetchedAt: now)

        var fetchInvoked = false
        let result = try await cache.tokens(for: .ethereum, now: now.addingTimeInterval(ttl - 1)) {
            fetchInvoked = true
            return [self.makeToken("DAI")]
        }

        XCTAssertFalse(fetchInvoked, "Fetch must not run for a fresh entry")
        XCTAssertEqual(result, stored)
        XCTAssertEqual(cache.cached(for: .ethereum), stored)
    }

    // (b) Past TTL invokes fetch and updates the cache.
    func testPastTTLInvokesFetchAndUpdates() async throws {
        let cache = SwapTokenListCache(ttl: ttl)
        let old = [makeToken("OLD")]
        let now = Date()
        cache.setCached(old, for: .ethereum, fetchedAt: now)

        let fresh = [makeToken("NEW")]
        var fetchInvoked = false
        let result = try await cache.tokens(for: .ethereum, now: now.addingTimeInterval(ttl + 1)) {
            fetchInvoked = true
            return fresh
        }

        XCTAssertTrue(fetchInvoked, "Fetch must run for a stale entry")
        XCTAssertEqual(result, fresh)
        XCTAssertEqual(cache.cached(for: .ethereum), fresh)
        XCTAssertFalse(cache.isStale(.ethereum, now: now.addingTimeInterval(ttl + 1)))
    }

    // (c) Per-chain isolation — fetching chain B does not evict a fresh chain A.
    func testPerChainIsolation() async throws {
        let cache = SwapTokenListCache(ttl: ttl)
        let now = Date()
        let ethTokens = [makeToken("USDC", chain: .ethereum)]
        cache.setCached(ethTokens, for: .ethereum, fetchedAt: now)

        let solTokens = [makeToken("USDC", chain: .solana)]
        _ = try await cache.tokens(for: .solana, now: now) { solTokens }

        XCTAssertEqual(cache.cached(for: .ethereum), ethTokens, "Chain A entry must survive a chain B fetch")
        XCTAssertEqual(cache.cached(for: .solana), solTokens)
    }

    // (d) Fail-open — returns last-good when the fetch closure throws.
    func testFailOpenReturnsLastGoodOnFetchError() async throws {
        let cache = SwapTokenListCache(ttl: ttl)
        let lastGood = [makeToken("USDC")]
        let now = Date()
        cache.setCached(lastGood, for: .ethereum, fetchedAt: now)

        let result = try await cache.tokens(for: .ethereum, now: now.addingTimeInterval(ttl + 1)) {
            throw FetchError()
        }

        XCTAssertEqual(result, lastGood, "Stale-but-present entry must be served when refetch fails")
    }

    // Cancellation must propagate even with a stale entry — fail-open is for real
    // fetch failures, not cooperative cancellation (the caller is tearing down).
    func testCancellationErrorPropagatesWithStaleEntry() async {
        let cache = SwapTokenListCache(ttl: ttl)
        let now = Date()
        cache.setCached([makeToken("USDC")], for: .ethereum, fetchedAt: now.addingTimeInterval(-ttl - 1))

        do {
            _ = try await cache.tokens(for: .ethereum, now: now) {
                throw CancellationError()
            }
            XCTFail("Expected CancellationError to propagate, not fail-open to stale")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // (d') With no prior entry, a fetch error propagates.
    func testFetchErrorPropagatesWhenNoPriorEntry() async {
        let cache = SwapTokenListCache(ttl: ttl)
        do {
            _ = try await cache.tokens(for: .ethereum) { throw FetchError() }
            XCTFail("Expected error to propagate with no last-good entry")
        } catch is FetchError {
            // expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // (e) In-flight coalescing — two concurrent calls → fetch runs once.
    func testInFlightCoalescingRunsFetchOnce() async throws {
        let cache = SwapTokenListCache(ttl: ttl)
        let counter = FetchCounter()
        let tokens = [makeToken("USDC")]

        async let first = cache.tokens(for: .ethereum) {
            await counter.increment()
            try? await Task.sleep(nanoseconds: 50_000_000)
            return tokens
        }
        async let second = cache.tokens(for: .ethereum) {
            await counter.increment()
            try? await Task.sleep(nanoseconds: 50_000_000)
            return tokens
        }

        let results = try await [first, second]
        let count = await counter.value
        XCTAssertEqual(count, 1, "Concurrent calls for the same chain must share one fetch")
        XCTAssertEqual(results[0], tokens)
        XCTAssertEqual(results[1], tokens)
    }

    func testClearCacheDropsEntries() {
        let cache = SwapTokenListCache(ttl: ttl)
        cache.setCached([makeToken("USDC")], for: .ethereum)
        XCTAssertNotNil(cache.cached(for: .ethereum))
        cache.clearCache()
        XCTAssertNil(cache.cached(for: .ethereum))
        XCTAssertTrue(cache.isStale(.ethereum))
    }
}

/// Actor counter so concurrent fetch closures can increment safely.
private actor FetchCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
