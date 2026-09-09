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
        XCTAssertFalse(TokenVerification.scam.autoSurfaces, "Scam must never auto-surface")
    }

    /// Rank orders authority, not trust: a positive identification says more
    /// than a source-side allowlist, and the in-code bundled list says most of
    /// all. `autoSurfaces` — not rank — is what keeps a scam off a screen.
    func testScamOutranksAllowlistsButNotTheBundledList() {
        XCTAssertGreaterThan(TokenVerification.scam.rank, TokenVerification.verified(source: "ton-assets").rank)
        XCTAssertGreaterThan(TokenVerification.scam.rank, TokenVerification.unverified.rank)
        XCTAssertGreaterThan(TokenVerification.curated.rank, TokenVerification.scam.rank)
    }

    func testSourceLabel() {
        XCTAssertEqual(TokenVerification.verified(source: "CoinGecko").sourceLabel, "CoinGecko")
        XCTAssertNil(TokenVerification.curated.sourceLabel)
        XCTAssertNil(TokenVerification.unverified.sourceLabel)
        XCTAssertNil(TokenVerification.scam.sourceLabel)
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

    /// A provider that merely does not recognise the address must not erase a
    /// positive identification, in either argument position.
    func testStrongerKeepsScamOverIgnorance() {
        XCTAssertEqual(TokenVerification.stronger(.scam, .unverified), .scam)
        XCTAssertEqual(TokenVerification.stronger(.unverified, .scam), .scam)
        XCTAssertEqual(TokenVerification.stronger(.scam, .verified(source: "ton-assets")), .scam)
        XCTAssertEqual(TokenVerification.stronger(.verified(source: "1inch"), .scam), .scam)
    }

    /// The bundled list is in-code and cannot be tampered with, so nothing —
    /// including a `.scam` restored from the untrusted disk snapshot — may
    /// suppress a curated token.
    func testStrongerNeverLetsScamDisplaceCurated() {
        XCTAssertEqual(TokenVerification.stronger(.curated, .scam), .curated)
        XCTAssertEqual(TokenVerification.stronger(.scam, .curated), .curated)
    }

    /// Preserved rather than downgraded: the worst a tampered `.scam` can do is
    /// hide a non-curated token from search, which is the fail-closed direction.
    func testScamSurvivesUntrustedPersistence() {
        XCTAssertEqual(TokenVerification.scam.cappedForUntrustedPersistence, .scam)
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
