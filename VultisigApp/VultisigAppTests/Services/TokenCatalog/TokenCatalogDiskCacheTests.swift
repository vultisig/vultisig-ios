//
//  TokenCatalogDiskCacheTests.swift
//  VultisigAppTests
//
//  The per-chain offline snapshot: round-trips the CoinMeta, and — the trust
//  invariant — caps every loaded token at `.verified` so untrusted persistence
//  can never confer `.curated` (the dedup-winning tier). `.verified`/`.unverified`
//  are preserved so a provider's last-good verified list still surfaces on a
//  transient outage.
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

    func testSaveLoadRoundTripsMetaAndPreservesVerifiedTiers() {
        let cache = makeCache()
        let tokens = [
            CatalogToken(meta: coin("USDC", "0x1"), verification: .verified(source: "CoinGecko"), sourceKind: "oneinch"),
            CatalogToken(meta: coin("DAI", "0x2"), verification: .unverified, sourceKind: "oneinch")
        ]
        cache.save(tokens, chain: .ethereum)
        let loaded = cache.load(chain: .ethereum)

        // CoinMeta + sourceKind round-trip; verified/unverified tiers are preserved
        // (so a last-good verified list survives an outage).
        XCTAssertEqual(loaded?.map { $0.meta }, tokens.map { $0.meta })
        XCTAssertEqual(loaded?.map { $0.sourceKind }, tokens.map { $0.sourceKind })
        XCTAssertEqual(loaded?.map { $0.verification }, [.verified(source: "CoinGecko"), .unverified])
    }

    func testLoadCapsCuratedToVerifiedButKeepsVerified() {
        let cache = makeCache()
        // A persisted .curated must never load as curated; a persisted .verified
        // stays verified (survives verification-to-surface on an outage).
        let tokens = [
            CatalogToken(meta: coin("USDC", "0x1"), verification: .curated, sourceKind: "x"),
            CatalogToken(meta: coin("DAI", "0x2"), verification: .verified(source: "CoinGecko"), sourceKind: "x")
        ]
        cache.save(tokens, chain: .ethereum)

        let loaded = cache.load(chain: .ethereum)
        XCTAssertEqual(loaded?.count, 2)
        XCTAssertNotEqual(loaded?.first?.verification, .curated, "A persisted token must never load as curated")
        XCTAssertEqual(loaded?.first?.verification, .verified(source: "cached"))
        XCTAssertEqual(loaded?.last?.verification, .verified(source: "CoinGecko"), "Verified stays verified")
        XCTAssertTrue(loaded?.allSatisfy { $0.autoSurfaces } ?? false, "Verified tiers still auto-surface offline")
    }

    func testRoundTripPreservesTheProvidersRankedOrder() {
        // Providers return their lists best-first and `CatalogToken` carries no
        // rank field, so order IS the ranking. A snapshot that round-tripped
        // through a set or re-sorted would silently degrade the offline browse
        // list to an arbitrary 20 tokens.
        let cache = makeCache()
        let ranked = (0..<50).map {
            CatalogToken(meta: coin("TKN\($0)", "0x\($0)"),
                         verification: .verified(source: "1inch"),
                         sourceKind: "oneinch")
        }
        cache.save(ranked, chain: .ethereum)

        let loaded = cache.load(chain: .ethereum)

        XCTAssertEqual(loaded?.map { $0.meta.ticker }, ranked.map { $0.meta.ticker },
                       "The offline snapshot must serve the list in the provider's ranked order")
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
