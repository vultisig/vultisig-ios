//
//  TokenMetadataResolverTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class TokenMetadataResolverTests: XCTestCase {
    private let usdcAddress = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

    func testResolveCachesSuccessfulFetch() async {
        let counter = CallCounter()
        let resolver = TokenMetadataResolver(fetcher: { _, _ in
            await counter.increment()
            return TokenMetadata(symbol: "USDC", decimals: 6)
        })

        let first = await resolver.resolve(contractAddress: usdcAddress, on: .ethereum)
        let second = await resolver.resolve(contractAddress: usdcAddress, on: .ethereum)

        XCTAssertEqual(first, TokenMetadata(symbol: "USDC", decimals: 6))
        XCTAssertEqual(second, first)
        let calls = await counter.value
        XCTAssertEqual(calls, 1, "Second call must hit the cache; fetcher invoked exactly once.")
    }

    func testResolveDifferentChainsCacheIndependently() async {
        let counter = CallCounter()
        let resolver = TokenMetadataResolver(fetcher: { chain, _ in
            await counter.increment()
            return TokenMetadata(symbol: chain == .ethereum ? "USDC" : "USDC.e", decimals: 6)
        })

        _ = await resolver.resolve(contractAddress: usdcAddress, on: .ethereum)
        _ = await resolver.resolve(contractAddress: usdcAddress, on: .arbitrum)
        let calls = await counter.value
        XCTAssertEqual(calls, 2, "Same address on different chains is a different cache key.")
    }

    func testResolveAddressIsCaseInsensitive() async {
        let counter = CallCounter()
        let resolver = TokenMetadataResolver(fetcher: { _, _ in
            await counter.increment()
            return TokenMetadata(symbol: "USDC", decimals: 6)
        })

        _ = await resolver.resolve(contractAddress: usdcAddress.lowercased(), on: .ethereum)
        _ = await resolver.resolve(contractAddress: usdcAddress.uppercased(), on: .ethereum)
        let calls = await counter.value
        XCTAssertEqual(calls, 1, "Different casings of the same address share a cache slot.")
    }

    func testResolveReturnsNilOnFetcherThrow() async {
        let resolver = TokenMetadataResolver(fetcher: { _, _ in
            throw TestError.boom
        })
        let result = await resolver.resolve(contractAddress: usdcAddress, on: .ethereum)
        XCTAssertNil(result)
    }

    func testResolveReturnsNilOnEmptySymbol() async {
        // `RpcEvmService.getTokenInfo` returns ("", "", 0) on its own internal failures.
        // The resolver must not cache that as a successful lookup.
        let resolver = TokenMetadataResolver(fetcher: { _, _ in
            TokenMetadata(symbol: "", decimals: 0)
        })
        let result = await resolver.resolve(contractAddress: usdcAddress, on: .ethereum)
        XCTAssertNil(result, "Empty symbol must be treated as a failed lookup.")
    }

    func testResolveReturnsNilOnUnreasonableDecimals() async {
        // A malicious / misbehaving contract could return any uint16+ value. Downstream
        // we compute `BigInt(10).power(decimals)`, which would chew CPU for huge values.
        let resolver = TokenMetadataResolver(fetcher: { _, _ in
            TokenMetadata(symbol: "EVIL", decimals: 65535)
        })
        let result = await resolver.resolve(contractAddress: usdcAddress, on: .ethereum)
        XCTAssertNil(result, "Decimals outside the sane range must be treated as a failed lookup.")
    }

    func testResolveAcceptsBoundaryDecimals() async {
        let resolver = TokenMetadataResolver(fetcher: { _, _ in
            TokenMetadata(symbol: "EDGE", decimals: 36)
        })
        let result = await resolver.resolve(contractAddress: usdcAddress, on: .ethereum)
        XCTAssertEqual(result, TokenMetadata(symbol: "EDGE", decimals: 36))
    }

    func testResolveDoesNotCacheFailures() async {
        let counter = CallCounter()
        let shouldFail = AtomicBool(true)
        let resolver = TokenMetadataResolver(fetcher: { _, _ in
            await counter.increment()
            if await shouldFail.value {
                throw TestError.boom
            }
            return TokenMetadata(symbol: "USDC", decimals: 6)
        })

        let firstFailed = await resolver.resolve(contractAddress: usdcAddress, on: .ethereum)
        XCTAssertNil(firstFailed)

        await shouldFail.set(false)
        let secondSucceeded = await resolver.resolve(contractAddress: usdcAddress, on: .ethereum)
        XCTAssertEqual(secondSucceeded, TokenMetadata(symbol: "USDC", decimals: 6))

        let calls = await counter.value
        XCTAssertEqual(calls, 2, "Failures must not poison the cache; the second call must retry.")
    }

    func testResolveSingleFlightsConcurrentCalls() async {
        let counter = CallCounter()
        let resolver = TokenMetadataResolver(fetcher: { _, _ in
            await counter.increment()
            // Simulate slow RPC so the second caller arrives mid-flight.
            try? await Task.sleep(nanoseconds: 50_000_000)
            return TokenMetadata(symbol: "USDC", decimals: 6)
        })

        async let first = resolver.resolve(contractAddress: usdcAddress, on: .ethereum)
        async let second = resolver.resolve(contractAddress: usdcAddress, on: .ethereum)
        async let third = resolver.resolve(contractAddress: usdcAddress, on: .ethereum)

        let results = await [first, second, third]
        XCTAssertEqual(results.compactMap { $0 }.count, 3)
        let calls = await counter.value
        XCTAssertEqual(calls, 1, "Concurrent resolves of the same key must dedupe to one fetch.")
    }

    func testResolveRefetchesAfterTTL() async {
        let counter = CallCounter()
        let clock = MutableClock(start: Date(timeIntervalSince1970: 0))
        let resolver = TokenMetadataResolver(
            ttl: 100,
            now: { clock.now },
            fetcher: { _, _ in
                await counter.increment()
                return TokenMetadata(symbol: "USDC", decimals: 6)
            }
        )

        _ = await resolver.resolve(contractAddress: usdcAddress, on: .ethereum)
        clock.advance(by: 99)
        _ = await resolver.resolve(contractAddress: usdcAddress, on: .ethereum)
        let beforeExpiry = await counter.value
        XCTAssertEqual(beforeExpiry, 1)

        clock.advance(by: 2) // cross 101s — past TTL
        _ = await resolver.resolve(contractAddress: usdcAddress, on: .ethereum)
        let afterExpiry = await counter.value
        XCTAssertEqual(afterExpiry, 2)
    }
}

// MARK: - Test helpers

private actor CallCounter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
}

private actor AtomicBool {
    private var stored: Bool
    init(_ initial: Bool) { stored = initial }
    var value: Bool { stored }
    func set(_ next: Bool) { stored = next }
}

/// `Date()`-backed clocks aren't time-travel-friendly. This is a `Sendable` clock the
/// resolver uses through its `now` injection.
private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(start: Date) { current = start }
    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }
    func advance(by seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }
}

private enum TestError: Error { case boom }
