//
//  CatalogTokenTests.swift
//  VultisigAppTests
//
//  Covers the trust wrapper (`TokenVerification` + `CatalogToken`) that phase 1
//  of the dynamic token catalog introduces. The load-bearing invariant: trust
//  lives on the wrapper, NOT on `CoinMeta` — so `CoinMeta.uniqueId`/`==`/`hash`
//  are untouched by verification and every existing dedup keeps working.
//

import XCTest
@testable import VultisigApp

final class CatalogTokenTests: XCTestCase {

    private func coin(ticker: String = "USDC", contract: String = "0xabc") -> CoinMeta {
        CoinMeta(
            chain: .ethereum,
            ticker: ticker,
            logo: "",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: contract,
            isNativeToken: false
        )
    }

    // MARK: - TokenVerification ranking

    func testVerificationRankOrder() {
        XCTAssertGreaterThan(TokenVerification.curated.rank, TokenVerification.verified(source: "CoinGecko").rank)
        XCTAssertGreaterThan(TokenVerification.verified(source: "CoinGecko").rank, TokenVerification.unverified.rank)
    }

    func testAutoSurfaceGate() {
        XCTAssertTrue(TokenVerification.curated.autoSurfaces)
        XCTAssertTrue(TokenVerification.verified(source: "Jupiter").autoSurfaces)
        XCTAssertFalse(TokenVerification.unverified.autoSurfaces, "Unverified must never auto-surface")
    }

    func testSourceLabel() {
        XCTAssertEqual(TokenVerification.verified(source: "CoinGecko").sourceLabel, "CoinGecko")
        XCTAssertNil(TokenVerification.curated.sourceLabel)
        XCTAssertNil(TokenVerification.unverified.sourceLabel)
    }

    func testStrongerKeepsHigherRank() {
        XCTAssertEqual(
            TokenVerification.stronger(.unverified, .verified(source: "CoinGecko")),
            .verified(source: "CoinGecko")
        )
        XCTAssertEqual(
            TokenVerification.stronger(.verified(source: "CoinGecko"), .curated),
            .curated
        )
        // Tie keeps lhs (deterministic).
        XCTAssertEqual(
            TokenVerification.stronger(.verified(source: "A"), .verified(source: "B")),
            .verified(source: "A")
        )
    }

    // MARK: - CatalogToken

    func testUniqueIdPassesThroughToMeta() {
        let token = CatalogToken(meta: coin(), verification: .curated, sourceKind: "bundled")
        XCTAssertEqual(token.uniqueId, token.meta.uniqueId)
    }

    func testAutoSurfacesMirrorsVerification() {
        XCTAssertTrue(CatalogToken(meta: coin(), verification: .curated, sourceKind: "bundled").autoSurfaces)
        XCTAssertFalse(CatalogToken(meta: coin(), verification: .unverified, sourceKind: "oneinch").autoSurfaces)
    }

    /// The invariant #4941 makes non-negotiable: wrapping the same `CoinMeta`
    /// with different verifications must not change the `CoinMeta`'s identity.
    func testVerificationDoesNotLeakIntoCoinMetaIdentity() {
        let meta = coin()
        let curated = CatalogToken(meta: meta, verification: .curated, sourceKind: "bundled")
        let unverified = CatalogToken(meta: meta, verification: .unverified, sourceKind: "oneinch")

        // CoinMeta identity is unaffected by the wrapper's verification.
        XCTAssertEqual(curated.meta, unverified.meta)
        XCTAssertEqual(curated.meta.uniqueId, unverified.meta.uniqueId)
        XCTAssertEqual(curated.meta.hashValue, unverified.meta.hashValue)

        // The wrappers themselves differ (verification is part of CatalogToken).
        XCTAssertNotEqual(curated, unverified)
    }

    func testCoinMetaEqualityIgnoresVerificationEntirely() {
        // Two metas that are `==` (same chain+ticker+contract) collapse in a Set
        // regardless of the verification a wrapper would carry — proving trust is
        // not part of the dedup key.
        let a = coin(ticker: "USDC", contract: "0xABC")
        let b = coin(ticker: "usdc", contract: "0xabc") // case-different, same identity
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set([a, b]).count, 1)
    }

    func testCatalogTokenCodableRoundTrip() throws {
        let original = CatalogToken(meta: coin(), verification: .verified(source: "CoinGecko"), sourceKind: "oneinch")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CatalogToken.self, from: data)
        XCTAssertEqual(original, decoded)
        XCTAssertEqual(decoded.verification, .verified(source: "CoinGecko"))
    }
}
