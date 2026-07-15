//
//  SecuredAssetTokenProviderTests.swift
//  VultisigAppTests
//
//  Covers `SecuredAssetTokenProvider` — the destination-token source that
//  surfaces the THORChain secured-asset universe in the swap coin picker.
//  Asserts the `.thorChain` bucket is populated, every other chain gets an
//  empty bucket, the static fallback keeps discovery working when the live
//  fetch fails, and that a held secured coin dedups onto its catalog twin
//  (no double-list) via the picker's merge.
//

import XCTest
@testable import VultisigApp

@MainActor
final class SecuredAssetTokenProviderTests: XCTestCase {

    private enum StubError: Error { case unavailable }

    private func makeProvider(assets: [ThorchainSecuredAsset]) -> SecuredAssetTokenProvider {
        SecuredAssetTokenProvider(catalog: SecuredAssetCatalog(fetch: { assets }))
    }

    // MARK: - Bucket population

    func testThorChainBucketPopulated() async {
        let provider = makeProvider(assets: [
            ThorchainSecuredAsset(asset: "BTC-BTC", supply: nil, depth: nil),
            ThorchainSecuredAsset(asset: "ETH-USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48", supply: nil, depth: nil)
        ])

        let bucket = await provider.tokens(for: .thorChain, forceRefresh: false)

        XCTAssertEqual(bucket.chain, .thorChain)
        XCTAssertEqual(bucket.tokens.count, 2)
        XCTAssertEqual(Set(bucket.tokens.map(\.ticker)), ["BTC", "USDC"])
        XCTAssertTrue(bucket.tokens.allSatisfy { !$0.isNativeToken })
        // Denom lowercased so a held secured coin (persisted lowercase) dedups.
        XCTAssertTrue(bucket.tokens.allSatisfy { $0.contractAddress == $0.contractAddress.lowercased() })
        XCTAssertEqual(bucket.uniqueIds, Set(bucket.tokens.map(\.uniqueId)))
    }

    /// A secured asset the vault holds zero of is still surfaced — the provider
    /// never consults holdings, so zero-balance destinations are discoverable.
    func testZeroBalanceSecuredAssetIsSurfaced() async {
        let provider = makeProvider(assets: [
            ThorchainSecuredAsset(asset: "GAIA-ATOM", supply: nil, depth: nil)
        ])

        let bucket = await provider.tokens(for: .thorChain, forceRefresh: false)

        XCTAssertEqual(bucket.tokens.map(\.ticker), ["ATOM"])
    }

    func testNonThorChainReturnsEmptyBucket() async {
        let provider = makeProvider(assets: [
            ThorchainSecuredAsset(asset: "BTC-BTC", supply: nil, depth: nil)
        ])

        for chain in [Chain.ethereum, .avalanche, .base, .arbitrum, .bscChain] {
            let bucket = await provider.tokens(for: chain, forceRefresh: false)
            XCTAssertEqual(bucket.chain, chain)
            XCTAssertTrue(bucket.tokens.isEmpty, "\(chain) must get an empty bucket — secured assets live only on THORChain")
        }
    }

    // MARK: - Fallback

    func testFallbackKeepsBucketPopulatedWhenFetchFails() async {
        let catalog = SecuredAssetCatalog(fetch: { throw StubError.unavailable })
        let provider = SecuredAssetTokenProvider(catalog: catalog)

        let bucket = await provider.tokens(for: .thorChain, forceRefresh: false)

        XCTAssertFalse(bucket.tokens.isEmpty, "Static fallback keeps discovery working when the live fetch fails")
        XCTAssertTrue(bucket.tokens.contains { $0.ticker == "BTC" })
    }

    // MARK: - Dedup with a held secured coin (picker merge)

    /// A held secured coin and its discovery-catalog twin share a `uniqueId`
    /// (chain + lowercased ticker + lowercased contract), so the picker's merge
    /// collapses them into a single row rather than double-listing.
    func testHeldSecuredCoinDedupesOntoCatalogTwin() {
        let discovered = SecuredAssetMapper.coinMeta(forDenom: "btc-btc")
        let bucket = DestinationTokenBucket(
            chain: .thorChain,
            tokens: [discovered],
            uniqueIds: [discovered.uniqueId]
        )

        // Provider bucket merges before vault tokens, mirroring `assemble`.
        let merged = SwapCoinSelectionLogic.mergeExternal(base: [], externals: [bucket])
        let heldTwin = SecuredAssetMapper.coinMeta(forDenom: "btc-btc")
        let withVault = SwapCoinSelectionLogic.merge(base: merged, extra: [heldTwin])

        XCTAssertEqual(withVault.count, 1, "Held secured coin must not double-list its catalog twin")
        XCTAssertEqual(withVault.first?.ticker, "BTC")
    }
}
