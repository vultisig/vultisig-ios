//
//  SwapKitTokensPickerFlagTests.swift
//  VultisigAppTests
//
//  Pins the destination-coin-picker invariant for the SwapKit token-list
//  expansion: the merge step prepends SwapKit's novel tokens to the
//  curated/1inch/Jupiter union and tags only the residual SwapKit-only
//  entries.
//

import XCTest
@testable import VultisigApp

final class SwapKitTokensPickerFlagTests: XCTestCase {

    func testMergeExternalAppendsNovelTokens() throws {
        // Base list (e.g. from 1inch + curated) has ETH-ETH + USDC. An external
        // provider's bucket adds a token the base list doesn't know about
        // (`NOVL`) — it must append to the merged list.
        let base: [CoinMeta] = [
            CoinMeta(chain: .ethereum, ticker: "ETH", logo: "", decimals: 18, priceProviderId: "ethereum", contractAddress: "", isNativeToken: true),
            CoinMeta(chain: .ethereum, ticker: "USDC", logo: "", decimals: 6, priceProviderId: "usd-coin", contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", isNativeToken: false)
        ]
        let novel = CoinMeta(chain: .ethereum, ticker: "NOVL", logo: "", decimals: 18, priceProviderId: "", contractAddress: "0x0000000000000000000000000000000000000abc", isNativeToken: false)
        let bucket = DestinationTokenBucket(
            chain: .ethereum,
            tokens: [novel],
            uniqueIds: [novel.uniqueId]
        )
        let merged = SwapCoinSelectionLogic.mergeExternal(base: base, externals: [bucket])
        XCTAssertEqual(merged.count, 3, "Novel external token must append")
        XCTAssertEqual(merged.last?.ticker, "NOVL")
    }

    func testMergeExternalDropsTokensAlreadyInBase() throws {
        // Overlap case — 1inch already discovered USDC. SwapKit's USDC must
        // NOT duplicate in the picker.
        let usdc = CoinMeta(chain: .ethereum, ticker: "USDC", logo: "", decimals: 6, priceProviderId: "usd-coin", contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", isNativeToken: false)
        let base = [usdc]
        let bucket = DestinationTokenBucket(
            chain: .ethereum,
            tokens: [usdc],
            uniqueIds: [usdc.uniqueId]
        )
        let merged = SwapCoinSelectionLogic.mergeExternal(base: base, externals: [bucket])
        XCTAssertEqual(merged.count, 1, "Overlap must not duplicate")
    }

    func testCollapseToSingleNativeKeepsCuratedAndDropsStaleTickerNative() throws {
        // After the Toncoin → GRAM rebrand the curated native is GRAM, but
        // SwapKit's token list (and any legacy persisted coin) still surfaces
        // the native as "TON". Both are native + empty-contract, so the
        // uniqueId dedup keeps them separate. The picker must show one native.
        let gram = CoinMeta(chain: .ton, ticker: "GRAM", logo: "gram", decimals: 9, priceProviderId: "the-open-network", contractAddress: "", isNativeToken: true)
        let usdt = CoinMeta(chain: .ton, ticker: "USDT", logo: "usdt", decimals: 6, priceProviderId: "tether", contractAddress: "EQjetton", isNativeToken: false)
        let staleTon = CoinMeta(chain: .ton, ticker: "TON", logo: "https://example/ton.png", decimals: 9, priceProviderId: "the-open-network", contractAddress: "", isNativeToken: true)

        let collapsed = SwapCoinSelectionLogic.collapseToSingleNative([gram, usdt, staleTon])

        XCTAssertEqual(collapsed.map { $0.ticker }, ["GRAM", "USDT"], "Curated native kept, stale-ticker native dropped, non-native untouched")
        XCTAssertEqual(collapsed.filter { $0.isNativeToken }.count, 1, "Exactly one native asset per chain")
    }

    func testCollapseToSingleNativePreservesListWithoutDuplicateNatives() throws {
        let eth = CoinMeta(chain: .ethereum, ticker: "ETH", logo: "eth", decimals: 18, priceProviderId: "ethereum", contractAddress: "", isNativeToken: true)
        let usdc = CoinMeta(chain: .ethereum, ticker: "USDC", logo: "usdc", decimals: 6, priceProviderId: "usd-coin", contractAddress: "0xa0b8", isNativeToken: false)

        let collapsed = SwapCoinSelectionLogic.collapseToSingleNative([eth, usdc])

        XCTAssertEqual(collapsed.map { $0.ticker }, ["ETH", "USDC"], "No duplicate native → list unchanged")
    }

    @MainActor
    func testCacheSeededSnapshotReturnsBuckets() async {
        let novel = CoinMeta(chain: .arbitrum, ticker: "NOVL", logo: "", decimals: 18, priceProviderId: "", contractAddress: "0x000000000000000000000000000000000000000A", isNativeToken: false)
        let bucket = DestinationTokenBucket(
            chain: .arbitrum,
            tokens: [novel],
            uniqueIds: [novel.uniqueId]
        )
        let cache = SwapKitTokensCache()
        cache.setSnapshot(buckets: [.arbitrum: bucket])
        let read = await cache.tokens(for: .arbitrum)
        XCTAssertEqual(read.tokens.count, 1)
        XCTAssertEqual(read.tokens.first?.ticker, "NOVL")
    }
}
