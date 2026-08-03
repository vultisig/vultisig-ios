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

    private func makeCoin(
        chain: Chain,
        ticker: String,
        contractAddress: String = "",
        isNativeToken: Bool
    ) -> Coin {
        let meta = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: ticker.lowercased(),
            decimals: 9,
            priceProviderId: "",
            contractAddress: contractAddress,
            isNativeToken: isNativeToken
        )
        return Coin(asset: meta, address: "addr", hexPublicKey: "pub")
    }

    /// The native TON asset is `TON.GRAM` on the wire. SwapKit tracked the
    /// Toncoin → Gram rename, so the pre-rename `TON.TON` no longer resolves —
    /// quoting it fails with `tokenPriceUnavailable`. Verifiable against
    /// `GET https://api.vultisig.com/swapkit/tokens?provider=NEAR` (bare host,
    /// no `/v3`), which lists `TON.GRAM` and no `TON.TON` at all.
    func testAssetIdentifierUsesGramForTheNativeTonCoin() {
        let gram = makeCoin(chain: .ton, ticker: "GRAM", isNativeToken: true)

        XCTAssertEqual(SwapKitService().assetIdentifier(for: gram), "TON.GRAM")
    }

    /// A jetton keeps its own ticker and appends its contract — the native case
    /// must not bleed into it. Matches SwapKit's listed
    /// `TON.USDT-EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs`.
    func testAssetIdentifierKeepsTheJettonTickerAndContract() {
        let contract = "EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs"
        let usdt = makeCoin(chain: .ton, ticker: "USDT", contractAddress: contract, isNativeToken: false)

        XCTAssertEqual(SwapKitService().assetIdentifier(for: usdt), "TON.USDT-\(contract)")
    }

    /// A vault restored from a pre-rebrand backup still holds a `TON`-ticker'd
    /// native: the launch migration rewrites `vault.coins`, but an import lands
    /// after it has already run. Canonicalising against the curated store keeps
    /// that vault quotable instead of sending the dead `TON.TON`.
    func testAssetIdentifierCanonicalisesAnUnmigratedNativeTonCoin() {
        let legacy = makeCoin(chain: .ton, ticker: "TON", isNativeToken: true)

        XCTAssertEqual(SwapKitService().assetIdentifier(for: legacy), "TON.GRAM")
    }

    /// Canonicalisation is scoped to natives — a jetton that happens to carry a
    /// ticker matching nothing curated must still quote under its own.
    func testAssetIdentifierDoesNotCanonicaliseNonNativeTokens() {
        let jetton = makeCoin(chain: .ton, ticker: "TON", contractAddress: "EQjetton", isNativeToken: false)

        XCTAssertEqual(SwapKitService().assetIdentifier(for: jetton), "TON.TON-EQjetton")
    }

    func testAssetIdentifierLeavesOtherChainsUnchanged() {
        let eth = makeCoin(chain: .ethereum, ticker: "ETH", isNativeToken: true)
        let btc = makeCoin(chain: .bitcoin, ticker: "BTC", isNativeToken: true)

        XCTAssertEqual(SwapKitService().assetIdentifier(for: eth), "ETH.ETH")
        XCTAssertEqual(SwapKitService().assetIdentifier(for: btc), "BTC.BTC")
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
