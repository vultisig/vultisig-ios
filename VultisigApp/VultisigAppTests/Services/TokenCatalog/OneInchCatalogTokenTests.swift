//
//  OneInchCatalogTokenTests.swift
//  VultisigAppTests
//
//  The 1inch trust-signal fix: `toCatalogToken` must preserve the CoinGecko
//  legitimacy signal that `toCoinMeta` drops — so unverified 1inch tokens carry
//  `.unverified` and get gated by verification-to-surface instead of appearing
//  unbadged. Also covers the provider's chain guards.
//

import XCTest
@testable import VultisigApp

@MainActor
final class OneInchCatalogTokenTests: XCTestCase {

    private func token(providers: [String]?) -> OneInchToken {
        OneInchToken(address: "0xABC", symbol: "USDC", name: "USD Coin",
                     decimals: 6, logoURI: "https://logo", providers: providers)
    }

    func testCoinGeckoListedMapsToVerified() {
        let catalog = token(providers: ["CoinGecko", "1inch"]).toCatalogToken(chain: .ethereum, sourceKind: "oneinch")
        XCTAssertEqual(catalog.verification, .verified(source: "CoinGecko"))
        XCTAssertEqual(catalog.sourceKind, "oneinch")
        XCTAssertEqual(catalog.meta.ticker, "USDC")
        XCTAssertEqual(catalog.meta.contractAddress, "0xABC")
        XCTAssertEqual(catalog.meta.decimals, 6)
    }

    func testNonCoinGeckoMapsToUnverified() {
        let catalog = token(providers: ["SomeRandomList"]).toCatalogToken(chain: .ethereum, sourceKind: "oneinch")
        XCTAssertEqual(catalog.verification, .unverified, "Without CoinGecko, 1inch tokens are unverified")
        XCTAssertFalse(catalog.autoSurfaces)
    }

    func testNilProvidersMapsToUnverified() {
        let catalog = token(providers: nil).toCatalogToken(chain: .ethereum, sourceKind: "oneinch")
        XCTAssertEqual(catalog.verification, .unverified)
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
