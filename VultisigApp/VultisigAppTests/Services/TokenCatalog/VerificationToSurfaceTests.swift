//
//  VerificationToSurfaceTests.swift
//  VultisigAppTests
//
//  Step 6: only curated / verified candidates auto-surface in the search list;
//  unverified are withheld (scam / lookalike / dust defense). This pins the
//  filter TokenSearchService.fetchUncached applies to the catalog, using a fresh
//  repository so the shared singletons aren't polluted.
//

import XCTest
@testable import VultisigApp

@MainActor
final class VerificationToSurfaceTests: XCTestCase {

    private func meta(_ ticker: String, _ contract: String) -> CoinMeta {
        CoinMeta(chain: .ethereum, ticker: ticker, logo: "", decimals: 18,
                 priceProviderId: "", contractAddress: contract, isNativeToken: false)
    }

    /// Invokes the real production filter (`TokenSearchService.surfaceableTokens`)
    /// so these tests fail if the wiring changes — not a duplicated helper.
    private func surfaced(_ catalog: [CatalogToken]) -> [CoinMeta] {
        TokenSearchService.surfaceableTokens(from: catalog)
    }

    func testUnverifiedAreWithheldWhileCuratedAndVerifiedSurface() async {
        let repo = TokenCatalogRepository()
        repo.register(FixedCatalogProvider(kind: "src", precedence: 0, tokens: [
            CatalogToken(meta: meta("CUR", "0x1"), verification: .curated, sourceKind: "src"),
            CatalogToken(meta: meta("VER", "0x2"), verification: .verified(source: "CoinGecko"), sourceKind: "src"),
            CatalogToken(meta: meta("SCAM", "0x3"), verification: .unverified, sourceKind: "src")
        ]))

        let list = surfaced(await repo.catalog(for: .ethereum))
        let tickers = Set(list.map { $0.ticker })
        XCTAssertTrue(tickers.contains("CUR"))
        XCTAssertTrue(tickers.contains("VER"))
        XCTAssertFalse(tickers.contains("SCAM"), "Unverified tokens must not auto-surface")
    }

    func testUnverifiedThatCollidesWithCuratedStillSurfacesAsCurated() async {
        // A verified/curated token and an unverified lookalike sharing uniqueId:
        // the merge keeps the strongest verification, so it surfaces (as curated).
        let repo = TokenCatalogRepository()
        repo.register(FixedCatalogProvider(kind: "dyn", precedence: 0, tokens: [
            CatalogToken(meta: meta("USDC", "0xabc"), verification: .unverified, sourceKind: "dyn")
        ]))
        repo.register(FixedCatalogProvider(kind: "bundled", precedence: Int.max, tokens: [
            CatalogToken(meta: meta("USDC", "0xabc"), verification: .curated, sourceKind: "bundled")
        ]))

        let list = surfaced(await repo.catalog(for: .ethereum))
        XCTAssertEqual(list.map { $0.ticker }, ["USDC"], "The collision resolves to the curated token, which surfaces")
    }

    func testAllUnverifiedProducesEmptySurfacedList() async {
        let repo = TokenCatalogRepository()
        repo.register(FixedCatalogProvider(kind: "dyn", precedence: 0, tokens: [
            CatalogToken(meta: meta("A", "0x1"), verification: .unverified, sourceKind: "dyn"),
            CatalogToken(meta: meta("B", "0x2"), verification: .unverified, sourceKind: "dyn")
        ]))
        let list = surfaced(await repo.catalog(for: .ethereum))
        XCTAssertTrue(list.isEmpty)
    }
}

/// Emits a fixed CatalogToken list for its chain.
@MainActor
private final class FixedCatalogProvider: TokenCatalogProvider {
    let kind: String
    let precedence: Int
    private let tokens: [CatalogToken]

    init(kind: String, precedence: Int, tokens: [CatalogToken]) {
        self.kind = kind
        self.precedence = precedence
        self.tokens = tokens
    }

    // swiftlint:disable:next async_without_await
    func tokens(for chain: Chain, forceRefresh _: Bool) async -> DestinationTokenBucket {
        let metas = tokens.filter { $0.meta.chain == chain }.map(\.meta)
        return DestinationTokenBucket(chain: chain, tokens: metas, uniqueIds: Set(metas.map(\.uniqueId)))
    }

    // swiftlint:disable:next async_without_await
    func catalogTokens(for chain: Chain, forceRefresh _: Bool) async -> [CatalogToken] {
        tokens.filter { $0.meta.chain == chain }
    }
}
