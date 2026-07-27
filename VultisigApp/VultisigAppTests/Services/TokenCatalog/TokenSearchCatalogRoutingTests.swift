//
//  TokenSearchCatalogRoutingTests.swift
//  VultisigAppTests
//
//  Step 5 routes TokenSearchService's list through TokenCatalogRepository. This
//  pins the assembled shape the search list is built from (mirroring
//  `TokenSearchService.fetchUncached`): the app-catalog for a chain, minus
//  native tokens. Uses a fresh repository so the shared `appCatalog` /
//  `SwapTokenListCache` singletons aren't polluted across cases.
//

import XCTest
@testable import VultisigApp

@MainActor
final class TokenSearchCatalogRoutingTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "TokenSearchCatalogRoutingTests-\(UUID().uuidString)")!
    }

    /// The search list for a curated chain equals the curated non-native tokens
    /// (the bundled provider's contribution), matching the old preset behaviour.
    func testCuratedChainSearchListMatchesNonNativeCuratedTokens() async {
        let repo = TokenCatalogRepository()
        repo.register(BundledTokensProvider(defaults: makeDefaults()))

        // Mirror fetchUncached: catalog(for:) filtered to non-native metas.
        let searchList = await repo.catalog(for: .ethereum)
            .filter { !$0.meta.isNativeToken }
            .map { $0.meta }

        let expected = TokensStore.TokenSelectionAssets
            .filter { $0.chain == .ethereum && !$0.isNativeToken }

        XCTAssertEqual(Set(searchList.map { $0.uniqueId }), Set(expected.map { $0.uniqueId }))
        XCTAssertFalse(searchList.contains { $0.isNativeToken }, "Native tokens must be excluded from search")
    }

    /// The curated CoinMeta (logo / priceProviderId) wins over a same-uniqueId
    /// dynamic entry, so the search list keeps curated metadata.
    func testCuratedMetadataWinsOverDynamicDuplicate() async {
        let repo = TokenCatalogRepository()
        repo.register(BundledTokensProvider(defaults: makeDefaults()))

        // A curated ETH token we can collide against.
        guard let curated = TokensStore.TokenSelectionAssets.first(where: { $0.chain == .ethereum && !$0.isNativeToken }) else {
            return XCTFail("Expected a curated non-native Ethereum token")
        }
        let dynamicDuplicate = CoinMeta(
            chain: .ethereum, ticker: curated.ticker, logo: "attacker-logo", decimals: curated.decimals,
            priceProviderId: "attacker", contractAddress: curated.contractAddress, isNativeToken: false
        )
        repo.register(SingleTokenProvider(kind: "dyn", precedence: 5, token:
            CatalogToken(meta: dynamicDuplicate, verification: .unverified, sourceKind: "dyn")))

        let merged = await repo.catalog(for: .ethereum).first { $0.uniqueId == curated.uniqueId }
        XCTAssertEqual(merged?.meta.logo, curated.logo, "Curated logo must survive the collision")
        XCTAssertEqual(merged?.verification, .curated)
    }
}

/// Emits one fixed CatalogToken for its chain — a minimal dynamic provider.
@MainActor
private final class SingleTokenProvider: TokenCatalogProvider {
    let kind: String
    let precedence: Int
    private let token: CatalogToken

    init(kind: String, precedence: Int, token: CatalogToken) {
        self.kind = kind
        self.precedence = precedence
        self.token = token
    }

    // swiftlint:disable:next async_without_await
    func tokens(for chain: Chain, forceRefresh _: Bool) async -> DestinationTokenBucket {
        let metas = token.meta.chain == chain ? [token.meta] : []
        return DestinationTokenBucket(chain: chain, tokens: metas, uniqueIds: Set(metas.map(\.uniqueId)))
    }

    // swiftlint:disable:next async_without_await
    func catalogTokens(for chain: Chain, forceRefresh _: Bool) async -> [CatalogToken] {
        token.meta.chain == chain ? [token] : []
    }
}
