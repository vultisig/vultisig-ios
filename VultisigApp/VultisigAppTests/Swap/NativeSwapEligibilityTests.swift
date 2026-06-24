//
//  NativeSwapEligibilityTests.swift
//  VultisigAppTests
//
//  THORChain / Maya are offered at the chain level (no per-token allowlist), so
//  an EVM token on a supported chain overlaps with a native source and the live
//  quote decides the route. Token-level pool availability is surfaced in the
//  picker by `NativePoolTokenProvider`, which maps pool-ids to curated CoinMeta.
//

import XCTest
@testable import VultisigApp

@MainActor
final class NativeSwapEligibilityTests: XCTestCase {

    // MARK: - Chain-level provider eligibility

    func testEthereumTokenIsOfferedBothNativeProviders() {
        let usdc = makeCoin(.ethereum, ticker: "USDC", isNative: false)
        let providers = usdc.swapProviders
        XCTAssertTrue(providers.contains(.thorchain), "ETH tokens are offered THORChain at the chain level")
        XCTAssertTrue(providers.contains(.mayachain), "ETH tokens are offered Maya at the chain level")
    }

    func testCacaoToEthUsdcOverlapsOnMaya() {
        // The concrete #4615 regression: CACAO → ETH.USDC was invisible because
        // "USDC" wasn't in a static maya array. With chain-level eligibility the
        // pair overlaps on Maya and the route is attempted.
        let cacao = makeCoin(.mayaChain, ticker: "CACAO", isNative: true)
        let usdc = makeCoin(.ethereum, ticker: "USDC", isNative: false)
        let common = SwapCoinsResolver.resolveAllProviders(fromCoin: cacao, toCoin: usdc)
        XCTAssertTrue(common.contains(.mayachain), "CACAO → ETH.USDC must overlap on Maya")
    }

    func testArbitrumTokenOffersMaya() {
        let arbToken = makeCoin(.arbitrum, ticker: "LEO", isNative: false)
        XCTAssertTrue(arbToken.swapProviders.contains(.mayachain))
    }

    // MARK: - NativePoolTokenProvider pool-id → curated CoinMeta

    func testBucketizeMapsNativeAndTickerFallback() {
        // `ETH.ETH` resolves to the curated ethereum native; `ETH.USDC-0x…` with
        // an unknown contract falls back to a ticker match on curated USDC.
        let buckets = NativePoolTokenProvider.bucketize(assetIds: ["ETH.ETH", "ETH.USDC-0xdeadbeef"])
        let eth = buckets[.ethereum]
        XCTAssertNotNil(eth)
        XCTAssertTrue(eth?.tokens.contains(where: { $0.ticker.caseInsensitiveCompare("ETH") == .orderedSame }) ?? false)
        XCTAssertTrue(eth?.tokens.contains(where: { $0.ticker.caseInsensitiveCompare("USDC") == .orderedSame }) ?? false)
    }

    func testBucketizeDropsUnsupportedAndMalformed() {
        let buckets = NativePoolTokenProvider.bucketize(assetIds: ["GAIA.ATOM", "notanassetid", "ETH."])
        XCTAssertTrue(buckets.isEmpty, "Unsupported prefixes and malformed ids are dropped")
    }

    // MARK: - Helpers

    private func makeCoin(_ chain: Chain, ticker: String, isNative: Bool) -> Coin {
        let meta = CoinMeta.make(chain: chain, ticker: ticker, decimals: 18, isNativeToken: isNative)
        return Coin(asset: meta, address: "addr-\(ticker)", hexPublicKey: "")
    }
}
