//
//  TokenSelectionPoolTests.swift
//  VultisigAppTests
//
//  Pins the unified local-first token pool: browse shows local + verified (no
//  unverified), search adds the badged unverified long-tail, curated/local
//  tokens are ALWAYS searchable (even when the provider fetch throws), and the
//  merge is local-first / deduped.
//

import XCTest
@testable import VultisigApp

@MainActor
final class TokenSelectionPoolTests: XCTestCase {

    private func meta(_ ticker: String, contract: String, chain: Chain = .ethereum) -> CoinMeta {
        CoinMeta(chain: chain, ticker: ticker, logo: "logo", decimals: 18,
                 priceProviderId: "", contractAddress: contract, isNativeToken: false)
    }

    // MARK: - mergeLocalFirst (pure ordering / dedup)

    func testMergeLocalFirstKeepsOrderAndDedupsLocalWins() {
        let local = meta("USDC", contract: "0xUSDC")
        let dupFromProvider = meta("USDC", contract: "0xUSDC")   // same uniqueId
        let providerOnly = meta("PEPE", contract: "0xPEPE")

        let merged = TokenSelectionLogic.mergeLocalFirst([[local], [dupFromProvider, providerOnly]])

        XCTAssertEqual(merged.map { $0.ticker }, ["USDC", "PEPE"], "Duplicate collapses; local kept first")
        XCTAssertEqual(merged.first?.contractAddress, "0xUSDC", "Local-first: the local meta wins the collision")
    }

    // MARK: - held-coin enrichment matches by uniqueId, not ticker

    func testSelectedTokensMatchHeldByUniqueIdNotTicker() {
        // Vault holds a legit USDC. The catalog carries the real USDC plus an
        // unverified lookalike on a DIFFERENT contract sharing the ticker. Only
        // the held token may enter the held set — the lookalike must NOT ride in
        // by ticker match (which would auto-surface it in browse).
        let heldUSDC = Coin(asset: meta("USDC", contract: "0xReal"), address: "0xwallet", hexPublicKey: "pub")
        let realFromCatalog = meta("USDC", contract: "0xReal")
        let lookalike = meta("USDC", contract: "0xFAKE")

        let result = TokenSelectionLogic.shared.selectedTokens(
            chainCoins: [heldUSDC],
            tokens: [realFromCatalog, lookalike]
        )

        XCTAssertEqual(result.map { $0.contractAddress }, ["0xReal"],
                       "Held coin enriched by uniqueId; the unverified lookalike must not appear")
    }

    func testSearchShowsHeldTokenAlongsideSameTickerLookalike() {
        // Vault holds real USDC (contract A). Search for "usdc" over a pool that
        // has the held token plus an unverified lookalike USDC (contract B).
        // BOTH are returned: the held token so the search doesn't come back empty
        // for a token the user owns, the lookalike (badged) so the impersonation
        // risk is visible. Local-first order puts the held token ahead.
        let heldFromPool = meta("USDC", contract: "0xReal")
        let lookalike = meta("USDC", contract: "0xFAKE")

        let result = TokenSelectionLogic.shared.filteredTokens(
            searchText: "usdc",
            tokens: [heldFromPool, lookalike]
        )

        XCTAssertEqual(result.map { $0.contractAddress }, ["0xReal", "0xFAKE"],
                       "Search returns the held token first and still reveals the same-ticker lookalike")
    }

    func testPreExistingKeepsVettedPresetWhenHoldingSameTickerLookalike() {
        // Vault holds a lookalike AAVE on a bogus contract. The vetted curated
        // AAVE preset (real contract) must remain in browse — presets are
        // excluded only by exact uniqueId, not by shared ticker.
        let lookalike = Coin(asset: meta("AAVE", contract: "0xFAKEAAVE"), address: "0xw", hexPublicKey: "p")

        let presets = TokenSelectionLogic.shared.preExistingTokens(
            chain: .ethereum,
            chainCoins: [lookalike],
            hiddenTokens: []
        )

        XCTAssertTrue(presets.contains { $0.ticker.uppercased() == "AAVE" && $0.contractAddress.lowercased() != "0xfakeaave" },
                      "The vetted curated preset stays in browse despite a held same-ticker lookalike")
    }

    // MARK: - browse vs search (VM level)

    func testBrowseShowsVerifiedButNotUnverifiedWhileSearchRevealsUnverified() async {
        let verified = meta("ZVERIFIED", contract: "0xa11ce")
        let unverified = meta("ZUNVERIF", contract: "0xb0b")
        let result = TokenSearchResult(
            surfaceable: [verified],
            unverified: [unverified],
            verificationByUniqueId: [
                verified.uniqueId: .verified(source: "CoinGecko"),
                unverified.uniqueId: .unverified
            ]
        )
        let vm = TokenSelectionViewModel(loadCatalog: { _ in result })

        await vm.load(chain: .ethereum, vault: .example)

        // Browse: verified breadth present, unverified absent.
        XCTAssertTrue(vm.browseProviderTokens.contains { $0.uniqueId == verified.uniqueId })
        XCTAssertFalse(vm.browseProviderTokens.contains { $0.uniqueId == unverified.uniqueId },
                       "Unverified must not appear in browse")

        // Search reveals the unverified token, and it's flagged for the badge.
        vm.searchText = "zunverif"
        vm.updateSearchedTokens()
        XCTAssertTrue(vm.searchedTokens.contains { $0.uniqueId == unverified.uniqueId },
                      "Typing a query reveals the unverified long-tail")
        XCTAssertEqual(vm.verification(for: unverified), .unverified)
    }

    func testHeldCuratedTokenIsFoundBySearch() async {
        // The reported bug: searching "vult" on Ethereum returned nothing even
        // though VULT is a curated preset — because the vault HELD it, and held
        // tokens were dropped from both the search pool and the filter. A token
        // the user owns must still be findable.
        guard let vultMeta = TokensStore.TokenSelectionAssets.first(where: {
            $0.chain == .ethereum && $0.ticker.uppercased() == "VULT"
        }) else {
            return XCTFail("VULT must exist as an Ethereum preset")
        }

        let vault = Vault(name: "held-vult")
        vault.coins = [Coin(asset: vultMeta, address: "0xwallet", hexPublicKey: "pub")]

        let vm = TokenSelectionViewModel(loadCatalog: { _ in
            TokenSearchResult(surfaceable: [], unverified: [], verificationByUniqueId: [:])
        })
        await vm.load(chain: .ethereum, vault: vault)

        vm.searchText = "vult"
        vm.updateSearchedTokens()

        XCTAssertTrue(vm.searchedTokens.contains { $0.uniqueId == vultMeta.uniqueId },
                      "A held curated token must still be found by search")
    }

    // MARK: - local-first search regression (provider fetch throws)

    func testCuratedTokenStaysSearchableWhenProviderFetchThrows() async {
        struct FetchError: Error {}
        let vm = TokenSelectionViewModel(loadCatalog: { _ in throw FetchError() })

        await vm.load(chain: .ethereum, vault: .example)

        // AAVE is a curated Ethereum preset. It must be found by search even
        // though the provider fetch failed (fail-open to the local presets).
        vm.searchText = "aave"
        vm.updateSearchedTokens()

        XCTAssertTrue(vm.searchedTokens.contains { $0.ticker.uppercased() == "AAVE" },
                      "Curated/local tokens stay searchable when the provider fetch throws")
        XCTAssertNotNil(vm.error, "The fetch error is still recorded even though the list fails open")
    }

    func testCuratedPresetBrowsableWhenProviderFetchThrows() async {
        struct FetchError: Error {}
        let vm = TokenSelectionViewModel(loadCatalog: { _ in throw FetchError() })

        await vm.load(chain: .ethereum, vault: .example)

        XCTAssertTrue(vm.preExistTokens.contains { $0.ticker.uppercased() == "AAVE" },
                      "Curated presets render in browse regardless of the provider outcome")
        XCTAssertTrue(vm.browseProviderTokens.isEmpty, "No provider breadth when the fetch failed")
    }
}
