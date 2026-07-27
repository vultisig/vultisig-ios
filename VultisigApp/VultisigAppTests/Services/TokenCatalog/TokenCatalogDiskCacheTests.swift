//
//  TokenCatalogDiskCacheTests.swift
//  VultisigAppTests
//
//  The per-chain offline snapshot: round-trips the CoinMeta, and — the trust
//  invariant — floors every loaded token to `.unverified` so untrusted
//  persistence can never confer trust (a disk-loaded token doesn't auto-surface
//  on the strength of a persisted verification).
//

import XCTest
@testable import VultisigApp

final class TokenCatalogDiskCacheTests: XCTestCase {

    private func makeCache() -> TokenCatalogDiskCache {
        TokenCatalogDiskCache(namespace: "test-\(UUID().uuidString)")
    }

    private func coin(_ ticker: String, _ contract: String) -> CoinMeta {
        CoinMeta(chain: .ethereum, ticker: ticker, logo: "l", decimals: 6,
                 priceProviderId: "", contractAddress: contract, isNativeToken: false)
    }

    func testSaveLoadRoundTripsMetaAndFloorsVerification() {
        let cache = makeCache()
        let tokens = [
            CatalogToken(meta: coin("USDC", "0x1"), verification: .verified(source: "CoinGecko"), sourceKind: "oneinch"),
            CatalogToken(meta: coin("DAI", "0x2"), verification: .unverified, sourceKind: "oneinch")
        ]
        cache.save(tokens, chain: .ethereum)
        let loaded = cache.load(chain: .ethereum)

        // CoinMeta + sourceKind round-trip; verification is floored to unverified.
        XCTAssertEqual(loaded?.map { $0.meta }, tokens.map { $0.meta })
        XCTAssertEqual(loaded?.map { $0.sourceKind }, tokens.map { $0.sourceKind })
        XCTAssertEqual(loaded?.map { $0.verification }, [.unverified, .unverified])
    }

    func testLoadFloorsAnyPersistedTrustToUnverified() {
        let cache = makeCache()
        // Even a persisted .curated / .verified must never confer trust on load.
        let tokens = [
            CatalogToken(meta: coin("USDC", "0x1"), verification: .curated, sourceKind: "x"),
            CatalogToken(meta: coin("DAI", "0x2"), verification: .verified(source: "CoinGecko"), sourceKind: "x")
        ]
        cache.save(tokens, chain: .ethereum)

        let loaded = cache.load(chain: .ethereum)
        XCTAssertEqual(loaded?.count, 2)
        XCTAssertTrue(loaded?.allSatisfy { $0.verification == .unverified } ?? false,
                      "A persisted token must never load as curated or verified")
        XCTAssertTrue(loaded?.allSatisfy { !$0.autoSurfaces } ?? false)
    }

    func testLoadAbsentChainReturnsNil() {
        let cache = makeCache()
        XCTAssertNil(cache.load(chain: .solana))
    }

    func testPerChainIsolation() {
        let cache = makeCache()
        cache.save([CatalogToken(meta: coin("USDC", "0x1"), verification: .verified(source: "CoinGecko"), sourceKind: "oneinch")], chain: .ethereum)
        XCTAssertNil(cache.load(chain: .arbitrum), "Saving one chain must not surface for another")
        XCTAssertNotNil(cache.load(chain: .ethereum))
    }
}
