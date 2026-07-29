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

        XCTAssertTrue(vm.searchedTokens.contains { $0.uniqueId == vultMeta.uniqueId },
                      "A held curated token must still be found by search")
    }

    func testSearchResultsTrackTheLatestKeystroke() async {
        // Reported repro: typing "USDCC" showed USDC, then deleting the trailing
        // "C" (leaving "USDC") made it disappear — results lagged one keystroke
        // behind because the filter re-read `searchText` from a `@Published`
        // willSet subscriber, i.e. before the new value was stored.
        let usdc = meta("USDC", contract: "0xUSDC")
        let vm = TokenSelectionViewModel(loadCatalog: { _ in
            TokenSearchResult(
                surfaceable: [usdc],
                unverified: [],
                verificationByUniqueId: [usdc.uniqueId: .verified(source: "CoinGecko")]
            )
        })
        await vm.load(chain: .ethereum, vault: .example)

        vm.searchText = "usdcc"
        XCTAssertFalse(vm.searchedTokens.contains { $0.uniqueId == usdc.uniqueId },
                       "No token matches 'usdcc' — results must reflect THIS keystroke")

        vm.searchText = "usdc"
        XCTAssertTrue(vm.searchedTokens.contains { $0.uniqueId == usdc.uniqueId },
                      "Deleting the trailing C must bring USDC back on the same keystroke")
    }

    // MARK: - local-first search regression (provider fetch throws)

    func testCuratedTokenStaysSearchableWhenProviderFetchThrows() async {
        struct FetchError: Error {}
        let vm = TokenSelectionViewModel(loadCatalog: { _ in throw FetchError() })

        await vm.load(chain: .ethereum, vault: .example)

        // AAVE is a curated Ethereum preset. It must be found by search even
        // though the provider fetch failed (fail-open to the local presets).
        vm.searchText = "aave"

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

    // MARK: - browse is capped per provider; search is not

    /// `count` provider tokens with distinct tickers/contracts, in rank order.
    private func rankedBreadth(_ prefix: String, count: Int, sourceKind: String)
    -> (metas: [CoinMeta], sourceKinds: [String: String], verification: [String: TokenVerification]) {
        var metas: [CoinMeta] = []
        var sourceKinds: [String: String] = [:]
        var verification: [String: TokenVerification] = [:]
        for index in 0..<count {
            let token = meta("\(prefix)\(index)", contract: "0x\(prefix)\(index)")
            metas.append(token)
            sourceKinds[token.uniqueId] = sourceKind
            verification[token.uniqueId] = .verified(source: sourceKind)
        }
        return (metas, sourceKinds, verification)
    }

    func testBrowseCapsProviderBreadthButSearchStillReachesTheLongTail() async {
        // The reason the cap exists: 1inch offers ~2,200 tokens on Ethereum.
        // Browse must be a shortlist; search must still reach every one of them.
        let breadth = rankedBreadth("TKN", count: 600, sourceKind: "oneinch")
        let vm = TokenSelectionViewModel(loadCatalog: { _ in
            TokenSearchResult(
                surfaceable: breadth.metas,
                unverified: [],
                verificationByUniqueId: breadth.verification,
                sourceKindByUniqueId: breadth.sourceKinds
            )
        })

        await vm.load(chain: .ethereum, vault: .example)

        XCTAssertEqual(vm.browseProviderTokens.count, TokenSelectionLogic.browseTokensPerProvider,
                       "Browse shows only the head of one provider's list")
        XCTAssertEqual(vm.browseProviderTokens.first?.ticker, "TKN0", "Best-first order is preserved")
        XCTAssertEqual(vm.browseProviderTokens.last?.ticker, "TKN19")

        let rank500 = breadth.metas[499]
        XCTAssertFalse(vm.browseProviderTokens.contains { $0.uniqueId == rank500.uniqueId },
                       "A token ranked #500 is not in browse")

        vm.searchText = "tkn499"
        XCTAssertTrue(vm.searchedTokens.contains { $0.uniqueId == rank500.uniqueId },
                      "…but search still finds it — capping must never be why a token isn't found")
    }

    func testSearchIsNotTruncatedWhenManyTickersShareTheQuery() async {
        // A capped result list would hide a token purely because 100 other
        // tickers contain the same substring, which is the exact failure the
        // search escape hatch exists to prevent.
        // `ZQRY` rather than a real ticker stem, so the count isn't muddied by
        // curated Ethereum presets that also match.
        let breadth = rankedBreadth("ZQRY", count: 300, sourceKind: "oneinch")
        let vm = TokenSelectionViewModel(loadCatalog: { _ in
            TokenSearchResult(
                surfaceable: breadth.metas,
                unverified: [],
                verificationByUniqueId: breadth.verification,
                sourceKindByUniqueId: breadth.sourceKinds
            )
        })
        await vm.load(chain: .ethereum, vault: .example)

        vm.searchText = "zqry"

        XCTAssertEqual(vm.searchedTokens.count, 300, "Every match is reachable, not just the first page")
        XCTAssertEqual(vm.searchedTokens.first?.ticker, "ZQRY0", "Matches keep the providers' ranked order")
    }

    func testBrowseCapsEachProviderIndependently() async {
        let oneInch = rankedBreadth("ONE", count: 50, sourceKind: "oneinch")
        let jupiter = rankedBreadth("JUP", count: 50, sourceKind: "jupiter")
        let vm = TokenSelectionViewModel(loadCatalog: { _ in
            TokenSearchResult(
                surfaceable: oneInch.metas + jupiter.metas,
                unverified: [],
                verificationByUniqueId: oneInch.verification.merging(jupiter.verification) { first, _ in first },
                sourceKindByUniqueId: oneInch.sourceKinds.merging(jupiter.sourceKinds) { first, _ in first }
            )
        })

        await vm.load(chain: .ethereum, vault: .example)

        let limit = TokenSelectionLogic.browseTokensPerProvider
        XCTAssertEqual(vm.browseProviderTokens.count, limit * 2, "Two providers get a cap each, not one shared cap")
        XCTAssertEqual(vm.browseProviderTokens.filter { $0.ticker.hasPrefix("ONE") }.count, limit)
        XCTAssertEqual(vm.browseProviderTokens.filter { $0.ticker.hasPrefix("JUP") }.count, limit)
    }

    func testChainWithNoRemoteProviderIsUnaffectedByTheCap() async {
        // A UTXO/Cosmos chain has only the bundled provider, so every curated
        // token is already local — the cap must be a no-op there, not a
        // truncation of the curated list.
        let vm = TokenSelectionViewModel(loadCatalog: { _ in
            TokenSearchResult(surfaceable: [], unverified: [], verificationByUniqueId: [:])
        })

        await vm.load(chain: .thorChain, vault: .example)

        let curated = TokenSelectionLogic.shared.preExistingTokens(
            chain: .thorChain, chainCoins: [], hiddenTokens: []
        )
        XCTAssertEqual(vm.preExistTokens.map { $0.uniqueId }, curated.map { $0.uniqueId },
                       "The whole curated floor still renders")
        XCTAssertTrue(vm.browseProviderTokens.isEmpty, "Nothing to cap without a remote provider")
    }

    // MARK: - cappedPerProvider (pure)

    func testCapAppliesAfterLocalExclusionSoBrowseStillGetsAFullSlate() {
        // Order matters: capping first would let curated/hidden tokens that get
        // dropped later eat slots, leaving browse short of the cap.
        let breadth = rankedBreadth("TKN", count: 40, sourceKind: "oneinch")
        // The first 15 are curated presets already rendered locally.
        let localIds = Set(breadth.metas.prefix(15).map { $0.uniqueId })

        let afterExclusion = TokenSelectionLogic.shared.providerTokens(
            breadth.metas, excludingLocal: localIds, hiddenTokens: []
        )
        let capped = TokenSelectionLogic.cappedPerProvider(
            afterExclusion, sourceKindByUniqueId: breadth.sourceKinds
        )

        XCTAssertEqual(capped.count, TokenSelectionLogic.browseTokensPerProvider,
                       "Browse still gets a full slate of genuinely new tokens")
        XCTAssertEqual(capped.first?.ticker, "TKN15", "…starting after the locally-rendered ones")
    }

    func testBrowseStillGetsAFullSlateWhenTheProvidersHeadIsHeldOrHidden() async {
        // The same invariant through the view model, which is where the ordering
        // actually has to hold: capping before the local/hidden exclusion would
        // let these leading entries eat slots and leave browse short.
        let breadth = rankedBreadth("TKN", count: 60, sourceKind: "oneinch")
        let vault = Vault(name: "held-and-hidden")
        vault.coins = breadth.metas.prefix(10).map {
            Coin(asset: $0, address: "0xwallet", hexPublicKey: "pub")
        }
        vault.hiddenTokens = breadth.metas[10..<15].map {
            HiddenToken(chain: $0.chain, ticker: $0.ticker, contractAddress: $0.contractAddress)
        }

        let vm = TokenSelectionViewModel(loadCatalog: { _ in
            TokenSearchResult(
                surfaceable: breadth.metas,
                unverified: [],
                verificationByUniqueId: breadth.verification,
                sourceKindByUniqueId: breadth.sourceKinds
            )
        })
        await vm.load(chain: .ethereum, vault: vault)

        XCTAssertEqual(vm.browseProviderTokens.count, TokenSelectionLogic.browseTokensPerProvider,
                       "The 10 held + 5 hidden leading tokens must not eat browse slots")
        XCTAssertEqual(vm.browseProviderTokens.first?.ticker, "TKN15")
        XCTAssertFalse(vm.browseProviderTokens.contains { token in
            vault.hiddenTokens.contains { $0.matches(token) }
        }, "A user-hidden token never returns to browse")
    }

    // MARK: - retained catalog is scoped to its chain

    func testAFailedLoadForAnotherChainDoesNotBrowseThePreviousChainsTokens() async {
        // A failed fetch keeps the last-good catalog rather than blanking the
        // list — but only for the same chain. Retaining it across a chain change
        // would surface Ethereum tokens on a Solana picker.
        struct FetchError: Error {}
        let ethereumBreadth = rankedBreadth("ETHTKN", count: 30, sourceKind: "oneinch")

        let vm = TokenSelectionViewModel(loadCatalog: { chain in
            guard chain == .ethereum else { throw FetchError() }
            return TokenSearchResult(
                surfaceable: ethereumBreadth.metas,
                unverified: [],
                verificationByUniqueId: ethereumBreadth.verification,
                sourceKindByUniqueId: ethereumBreadth.sourceKinds
            )
        })

        await vm.load(chain: .ethereum, vault: .example)
        XCTAssertFalse(vm.browseProviderTokens.isEmpty)

        await vm.load(chain: .solana, vault: .example)

        XCTAssertTrue(vm.browseProviderTokens.isEmpty, "The other chain's breadth must be discarded")
        vm.searchText = "ethtkn"
        XCTAssertTrue(vm.searchedTokens.isEmpty, "…and must not be searchable either")
    }

    func testCapKeepsTokensWithAnUnknownSourceBoundedRatherThanUncapped() {
        let orphans = (0..<40).map { meta("ORPH\($0)", contract: "0xORPH\($0)") }

        let capped = TokenSelectionLogic.cappedPerProvider(orphans, sourceKindByUniqueId: [:])

        XCTAssertEqual(capped.count, TokenSelectionLogic.browseTokensPerProvider,
                       "An unattributed token shares one bucket — it must not escape the cap")
    }

    func testCapIsANoOpBelowTheLimit() {
        let breadth = rankedBreadth("TKN", count: 5, sourceKind: "oneinch")

        let capped = TokenSelectionLogic.cappedPerProvider(
            breadth.metas, sourceKindByUniqueId: breadth.sourceKinds
        )

        XCTAssertEqual(capped.map { $0.uniqueId }, breadth.metas.map { $0.uniqueId })
    }
}
