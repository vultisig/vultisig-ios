//
//  SwapKitTokensPickerFlagTests.swift
//  VultisigAppTests
//
//  Pins the destination-coin-picker invariant for the SwapKit token-list
//  expansion: when the feature flag is OFF, the cache's per-chain bucket is
//  empty (no `/tokens` fetch, no tag injection); when ON, the merge step
//  prepends SwapKit's novel tokens to the curated/1inch/Jupiter union and
//  tags only the residual SwapKit-only entries.
//

import XCTest
@testable import VultisigApp

final class SwapKitTokensPickerFlagTests: XCTestCase {

    private let flagKey = "swapkitEnabled"
    private var savedValue: Any?

    override func setUpWithError() throws {
        savedValue = UserDefaults.standard.object(forKey: flagKey)
        UserDefaults.standard.removeObject(forKey: flagKey)
    }

    override func tearDownWithError() throws {
        if let savedValue {
            UserDefaults.standard.set(savedValue, forKey: flagKey)
        } else {
            UserDefaults.standard.removeObject(forKey: flagKey)
        }
    }

    func testCacheReturnsEmptyBucketWhenFlagOff() async {
        UserDefaults.standard.set(false, forKey: flagKey)
        let cache = SwapKitTokensCache()
        let bucket = await cache.tokens(for: .ethereum)
        XCTAssertTrue(
            bucket.tokens.isEmpty,
            "Flag OFF must short-circuit the cache to an empty bucket — no SwapKit fetch, no tag injection"
        )
        XCTAssertTrue(bucket.uniqueIds.isEmpty)
    }

    func testMergeAppendsNovelSwapKitTokens() throws {
        // Base list (e.g. from 1inch + curated) has ETH-ETH + USDC. SwapKit's
        // bucket adds a token the base list doesn't know about (`NOVL`) — it
        // must append to the merged list.
        let base: [CoinMeta] = [
            CoinMeta(chain: .ethereum, ticker: "ETH", logo: "", decimals: 18, priceProviderId: "ethereum", contractAddress: "", isNativeToken: true),
            CoinMeta(chain: .ethereum, ticker: "USDC", logo: "", decimals: 6, priceProviderId: "usd-coin", contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", isNativeToken: false)
        ]
        let novel = CoinMeta(chain: .ethereum, ticker: "NOVL", logo: "", decimals: 18, priceProviderId: "", contractAddress: "0x0000000000000000000000000000000000000abc", isNativeToken: false)
        let bucket = SwapKitTokensBucket(
            chain: .ethereum,
            byIdentifier: ["ETH.NOVL-0x0000000000000000000000000000000000000abc": novel],
            uniqueIds: [novel.uniqueId]
        )
        let merged = SwapCoinSelectionLogic.mergeWithSwapKit(base: base, swapKit: bucket)
        XCTAssertEqual(merged.count, 3, "Novel SwapKit token must append")
        XCTAssertEqual(merged.last?.ticker, "NOVL")
    }

    func testMergeDropsSwapKitTokensAlreadyInBase() throws {
        // Overlap case — 1inch already discovered USDC. SwapKit's USDC must
        // NOT duplicate in the picker.
        let usdc = CoinMeta(chain: .ethereum, ticker: "USDC", logo: "", decimals: 6, priceProviderId: "usd-coin", contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", isNativeToken: false)
        let base = [usdc]
        let bucket = SwapKitTokensBucket(
            chain: .ethereum,
            byIdentifier: ["ETH.USDC-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48": usdc],
            uniqueIds: [usdc.uniqueId]
        )
        let merged = SwapCoinSelectionLogic.mergeWithSwapKit(base: base, swapKit: bucket)
        XCTAssertEqual(merged.count, 1, "Overlap must not duplicate")
    }

    func testCacheSeededSnapshotReturnsBucketsWhenFlagOn() async {
        UserDefaults.standard.set(true, forKey: flagKey)
        let novel = CoinMeta(chain: .arbitrum, ticker: "NOVL", logo: "", decimals: 18, priceProviderId: "", contractAddress: "0x000000000000000000000000000000000000000A", isNativeToken: false)
        let bucket = SwapKitTokensBucket(
            chain: .arbitrum,
            byIdentifier: ["ARB.NOVL-0x000000000000000000000000000000000000000A": novel],
            uniqueIds: [novel.uniqueId]
        )
        let cache = SwapKitTokensCache()
        await cache.setSnapshot(buckets: [.arbitrum: bucket])
        let read = await cache.tokens(for: .arbitrum)
        XCTAssertEqual(read.tokens.count, 1)
        XCTAssertEqual(read.tokens.first?.ticker, "NOVL")
    }
}
