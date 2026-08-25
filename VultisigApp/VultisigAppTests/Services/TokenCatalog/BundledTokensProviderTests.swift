//
//  BundledTokensProviderTests.swift
//  VultisigAppTests
//
//  The bundled provider is the curated offline floor of the token catalog.
//  Covers: it emits curated `TokensStore` tokens for a chain tagged `.curated`,
//  wins dedup via max precedence, and honors the same chain-visibility gates as
//  the coin-selection list (sepolia / thorchain-chainnet / QBTC-MLDSA).
//

import XCTest
@testable import VultisigApp

@MainActor
final class BundledTokensProviderTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "BundledTokensProviderTests-\(UUID().uuidString)")!
        return suite
    }

    func testEmitsCuratedTokensForChainTaggedCurated() async {
        let provider = BundledTokensProvider(defaults: makeDefaults())
        let catalog = await provider.catalogTokens(for: .ethereum)

        XCTAssertFalse(catalog.isEmpty, "Ethereum has curated tokens in TokensStore")
        XCTAssertTrue(catalog.allSatisfy { $0.verification == .curated }, "Every bundled token is curated")
        XCTAssertTrue(catalog.allSatisfy { $0.sourceKind == "bundled" })
        XCTAssertTrue(catalog.allSatisfy { $0.meta.chain == .ethereum })
    }

    func testMatchesTokensStoreForChain() async {
        let provider = BundledTokensProvider(defaults: makeDefaults())
        let catalog = await provider.catalogTokens(for: .ethereum)
        let expected = TokensStore.TokenSelectionAssets.filter { $0.chain == .ethereum }
        XCTAssertEqual(Set(catalog.map { $0.meta.uniqueId }), Set(expected.map { $0.uniqueId }))
    }

    func testEthereumThorUsesThorSwapPriceAndLogo() async throws {
        let provider = BundledTokensProvider(defaults: makeDefaults())
        let catalog = await provider.catalogTokens(for: .ethereum)
        let thor = try XCTUnwrap(catalog.first { $0.meta.contractAddress == TokensStore.ethTHOR.contractAddress })

        XCTAssertEqual(thor.meta.ticker, "THOR")
        XCTAssertEqual(thor.meta.logo, "thorswap")
        XCTAssertEqual(thor.meta.priceProviderId, "thorswap")
    }

    func testHighestPrecedenceWinsDedup() {
        // Bundled is Int.max so its CoinMeta always wins a uniqueId collision.
        XCTAssertEqual(BundledTokensProvider(defaults: makeDefaults()).precedence, Int.max)
    }

    // MARK: - Visibility gates

    func testThorchainChainnetGatedOffByDefault() {
        let defaults = makeDefaults()
        XCTAssertFalse(
            BundledTokensProvider.isChainVisible(.thorChainChainnet, defaults: defaults),
            "Thorchain chainnet hidden unless the flag is on"
        )
        XCTAssertFalse(BundledTokensProvider.isChainVisible(.thorChainStagenet, defaults: defaults))
        XCTAssertTrue(BundledTokensProvider.curatedTokens(for: .thorChainChainnet, defaults: defaults).isEmpty)
    }

    func testThorchainChainnetVisibleWhenEnabled() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "thorchainChainnet")
        XCTAssertTrue(BundledTokensProvider.isChainVisible(.thorChainChainnet, defaults: defaults))
        XCTAssertTrue(BundledTokensProvider.isChainVisible(.thorChainStagenet, defaults: defaults))
    }

    func testSepoliaGatedOffByDefault() {
        let defaults = makeDefaults()
        XCTAssertFalse(BundledTokensProvider.isChainVisible(.ethereumSepolia, defaults: defaults))
        XCTAssertTrue(BundledTokensProvider.curatedTokens(for: .ethereumSepolia, defaults: defaults).isEmpty)
        defaults.set(true, forKey: "sepolia")
        XCTAssertTrue(BundledTokensProvider.isChainVisible(.ethereumSepolia, defaults: defaults))
    }

    func testSepoliaNativeInjectedWhenEnabled() {
        // Sepolia's native token isn't in TokenSelectionAssets — the provider must
        // inject it (parity with CoinSelectionViewModel.groupAssets) when enabled.
        let defaults = makeDefaults()
        defaults.set(true, forKey: "sepolia")
        let tokens = BundledTokensProvider.curatedTokens(for: .ethereumSepolia, defaults: defaults)
        XCTAssertEqual(tokens, [TokensStore.Token.ethSepolia])
    }

    func testRegularChainAlwaysVisible() {
        let defaults = makeDefaults()
        XCTAssertTrue(BundledTokensProvider.isChainVisible(.ethereum, defaults: defaults))
        XCTAssertTrue(BundledTokensProvider.isChainVisible(.bitcoin, defaults: defaults))
    }
}
