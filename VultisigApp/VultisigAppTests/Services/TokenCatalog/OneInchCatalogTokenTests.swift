//
//  OneInchCatalogTokenTests.swift
//  VultisigAppTests
//
//  Trust mapping for the 1inch catalog path. `/swap/v6.0/{chain}/tokens` is
//  1inch's curated swap whitelist and carries NO `providers` field (that lives on
//  the separate `/token/v1.2/{chain}/custom` endpoint the EVM coin-finder uses),
//  so membership in the whitelist is the trust signal: `.verified("1inch")`,
//  downgraded to `.unverified` for the tokens 1inch itself tags `RISK:*`.
//

import XCTest
@testable import VultisigApp

@MainActor
final class OneInchCatalogTokenTests: XCTestCase {

    private func token(tags: [String]?, providers: [String]? = nil) -> OneInchToken {
        OneInchToken(address: "0xABC", symbol: "USDC", name: "USD Coin",
                     decimals: 6, logoURI: "https://logo", providers: providers, tags: tags)
    }

    // MARK: - The regression: the real `/tokens` payload has no `providers`

    /// Decodes the exact shape the endpoint returns (verified live: `address`,
    /// `symbol`, `decimals`, `name`, `logoURI`, `eip2612`, `tags` — no
    /// `providers`). A reputable token must come back verified, not unverified.
    func testLiveTokensPayloadShapeMapsToVerified() throws {
        let json = Data("""
        {
          "address": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
          "symbol": "USDC",
          "decimals": 6,
          "name": "USD Coin",
          "logoURI": "https://tokens.1inch.io/0xa0b8.png",
          "eip2612": true,
          "tags": ["connector", "defi", "PEG:USD", "RISK:norisk", "stablecoin"]
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(OneInchToken.self, from: json)

        XCTAssertNil(decoded.providers, "The /tokens whitelist never returns `providers`")
        XCTAssertFalse(decoded.isCoinGeckoVerified, "No CoinGecko signal is available on this endpoint")

        let catalog = decoded.toCatalogToken(chain: .ethereum, sourceKind: "oneinch")
        XCTAssertEqual(catalog.verification, .verified(source: "1inch"))
        XCTAssertTrue(catalog.autoSurfaces, "A 1inch-whitelisted token must surface in browse")
    }

    // MARK: - Whitelist membership is the signal

    func testWhitelistedTokenIsVerifiedByOneInch() {
        let catalog = token(tags: ["RISK:norisk", "stablecoin"]).toCatalogToken(chain: .ethereum, sourceKind: "oneinch")
        XCTAssertEqual(catalog.verification, .verified(source: "1inch"))
        XCTAssertEqual(catalog.verification.sourceLabel, "1inch",
                       "The label must name 1inch — there is no CoinGecko signal on this path")
        XCTAssertEqual(catalog.sourceKind, "oneinch")
        XCTAssertEqual(catalog.meta.ticker, "USDC")
        XCTAssertEqual(catalog.meta.contractAddress, "0xABC")
        XCTAssertEqual(catalog.meta.decimals, 6)
    }

    func testUntaggedTokenIsStillVerified() {
        // Much of the whitelist carries no RISK tag at all; absence of a flag is
        // not a reason to withhold — being on the list is the signal.
        XCTAssertEqual(token(tags: nil).toCatalogToken(chain: .ethereum, sourceKind: "oneinch").verification,
                       .verified(source: "1inch"))
        XCTAssertEqual(token(tags: []).toCatalogToken(chain: .ethereum, sourceKind: "oneinch").verification,
                       .verified(source: "1inch"))
    }

    func testAvailabilityRiskIsNotALegitimacySignal() {
        // `RISK:availability` is about routing/liquidity, not provenance.
        let catalog = token(tags: ["RISK:availability"]).toCatalogToken(chain: .ethereum, sourceKind: "oneinch")
        XCTAssertEqual(catalog.verification, .verified(source: "1inch"))
    }

    // MARK: - 1inch's own risk flags downgrade

    func testOneInchRiskFlagsDowngradeToUnverified() {
        for tag in ["RISK:malicious", "RISK:suspicious", "RISK:unverified"] {
            let catalog = token(tags: [tag, "tokens"]).toCatalogToken(chain: .ethereum, sourceKind: "oneinch")
            XCTAssertEqual(catalog.verification, .unverified, "\(tag) must not auto-surface")
            XCTAssertFalse(catalog.autoSurfaces, "\(tag) must not auto-surface")
        }
    }

    /// 1inch does emit conflicting pairs (`RISK:norisk` + `RISK:unverified`).
    /// Fail closed.
    func testConflictingRiskTagsFailClosed() {
        let catalog = token(tags: ["RISK:norisk", "RISK:unverified"])
            .toCatalogToken(chain: .ethereum, sourceKind: "oneinch")
        XCTAssertEqual(catalog.verification, .unverified)
    }

    /// A `RISK:` value 1inch adds after this ships must fail closed rather than
    /// auto-surfacing an unreviewed classification.
    func testUnknownRiskTagFailsClosed() {
        let catalog = token(tags: ["RISK:somethingNew"])
            .toCatalogToken(chain: .ethereum, sourceKind: "oneinch")
        XCTAssertEqual(catalog.verification, .unverified,
                       "An unrecognised RISK: classification must not auto-surface")
    }

    /// Only the `RISK:` family gates trust — descriptive tags must not.
    func testNonRiskTagsDoNotDowngrade() {
        let catalog = token(tags: ["stablecoin", "PEG:USD", "connector", "crosschain", "RWA"])
            .toCatalogToken(chain: .ethereum, sourceKind: "oneinch")
        XCTAssertEqual(catalog.verification, .verified(source: "1inch"))
    }

    /// The ⚠-badged unverified surface must stay reachable: 1inch's own risk
    /// flags are what keep it populated now that whitelist membership is trusted.
    func testUnverifiedSurfaceStaysReachableFromOneInch() {
        let candidates = [
            token(tags: ["RISK:norisk"]).toCatalogToken(chain: .ethereum, sourceKind: "oneinch"),
            OneInchToken(address: "0xDEF", symbol: "SCAM", name: "Scam", decimals: 18,
                         logoURI: "https://logo", providers: nil, tags: ["RISK:malicious"])
                .toCatalogToken(chain: .ethereum, sourceKind: "oneinch")
        ]

        let result = TokenSearchService.searchResult(from: candidates)

        XCTAssertEqual(result.surfaceable.map { $0.ticker }, ["USDC"])
        XCTAssertEqual(result.unverified.map { $0.ticker }, ["SCAM"],
                       "1inch's RISK-flagged tokens keep the badged unverified surface populated")
    }

    // MARK: - Provider guards

    func testProviderVouchesForItsWholeWhitelist() {
        XCTAssertEqual(OneInchCatalogProvider().verification, .verified(source: "1inch"),
                       "The provider baseline must not be `.unverified` any more")
    }

    func testProviderReturnsEmptyForUnsupportedChain() async {
        // Bitcoin is not an EVM chain 1inch supports.
        let provider = OneInchCatalogProvider()
        let catalog = await provider.catalogTokens(for: .bitcoin)
        XCTAssertTrue(catalog.isEmpty)
    }

    func testJupiterProviderReturnsEmptyForNonSolana() async {
        let provider = JupiterCatalogProvider()
        let catalog = await provider.catalogTokens(for: .ethereum)
        XCTAssertTrue(catalog.isEmpty)
        XCTAssertEqual(provider.verification, .verified(source: "Jupiter"),
                       "Jupiter's whole list is verified")
    }
}
