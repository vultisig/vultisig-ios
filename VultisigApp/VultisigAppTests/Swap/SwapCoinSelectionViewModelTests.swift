//
//  SwapCoinSelectionViewModelTests.swift
//  VultisigAppTests
//
//  Pins the swap "Select asset" picker's list/filter behavior:
//  - an empty query returns the full default list, a query filters by
//    ticker substring, and no match yields an empty list;
//  - the destination picker publishes the network-free local list
//    (curated native + cached external + vault coins) BEFORE the
//    destination-token providers return, so the sheet never sits on
//    "No result found." while a slow provider refresh is in flight;
//  - the source-side picker never consults the destination providers.
//

import XCTest
@testable import VultisigApp

@MainActor
final class SwapCoinSelectionViewModelTests: XCTestCase {

    override func tearDown() {
        SwapTokenListCache.shared.clearCache()
        super.tearDown()
    }

    // MARK: - filterTokens

    func testFilterTokensEmptyQueryReturnsDefaultList() {
        let logic = makeLogic()
        let tokens = [meta("ETH", isNative: true), meta("USDC"), meta("WBTC")]

        let filtered = logic.filterTokens(searchText: "", tokens: tokens)

        XCTAssertEqual(filtered, tokens, "Empty query must return the full default list, not an empty one")
    }

    func testFilterTokensQueryFiltersByTickerSubstring() {
        let logic = makeLogic()
        let tokens = [meta("ETH", isNative: true), meta("USDC"), meta("USDT"), meta("WBTC")]

        let filtered = logic.filterTokens(searchText: "usd", tokens: tokens)

        XCTAssertEqual(filtered.map { $0.ticker }, ["USDC", "USDT"])
    }

    func testFilterTokensNoMatchReturnsEmpty() {
        let logic = makeLogic()
        let tokens = [meta("ETH", isNative: true), meta("USDC")]

        let filtered = logic.filterTokens(searchText: "zzz", tokens: tokens)

        XCTAssertTrue(filtered.isEmpty)
    }

    // MARK: - Initial state defaults to loading

    func testInitialStateIsLoadingSoEmptyStateCannotRenderBeforeFirstPublish() async throws {
        let novel = meta("NOVL", contract: "0x000000000000000000000000000000000000abcd")
        let provider = GatedDestinationTokenProvider(
            bucket: DestinationTokenBucket(chain: .ethereum, tokens: [novel], uniqueIds: [novel.uniqueId])
        )
        let registry = DestinationTokenRegistry()
        registry.register(provider)

        SwapTokenListCache.shared.setCached([meta("USDC")], for: .ethereum)

        let vm = SwapCoinSelectionViewModel(
            vault: makeVault(),
            selectedCoin: makeCoin("ETH", isNative: true),
            isDestination: true,
            registry: registry
        )

        // Before any fetch, the view must resolve to the loader — never the
        // empty message — so the first frame cannot flash "No result found.".
        XCTAssertTrue(vm.isLoading, "A fresh view model must default to loading")
        XCTAssertTrue(vm.filteredTokens.isEmpty)

        let fetchTask = Task { await vm.fetchCoins(chain: .ethereum, forceRefresh: true) }
        defer { provider.release() }

        // At every observable point up to the first publish, the view must be
        // able to render either the loader or a non-empty list — never the
        // empty state.
        try await waitUntil("first publish") {
            XCTAssertTrue(
                vm.isLoading || !vm.filteredTokens.isEmpty,
                "Empty state must be unreachable before the first publish"
            )
            return !vm.filteredTokens.isEmpty
        }

        XCTAssertFalse(vm.isLoading, "The first publish must clear the loading state")

        // Finish the gated fetch inside the test so the enriched publish
        // can't run after the test exits (the defer above is then a no-op).
        provider.release()
        await fetchTask.value
    }

    func testNoMatchQueryAfterLoadStillShowsEmptyState() async throws {
        // After the first publish, a query with no match must land in the
        // genuine no-results state: not loading, nothing filtered.
        let registry = DestinationTokenRegistry()
        SwapTokenListCache.shared.setCached([meta("USDC")], for: .ethereum)

        let vm = SwapCoinSelectionViewModel(
            vault: makeVault(),
            selectedCoin: makeCoin("ETH", isNative: true),
            isDestination: true,
            registry: registry
        )
        vm.searchText = "zzz"

        await vm.fetchCoins(chain: .ethereum, forceRefresh: true)

        XCTAssertFalse(vm.isLoading, "Load finished — the empty state must be reachable again")
        XCTAssertTrue(vm.filteredTokens.isEmpty, "No ticker matches the query")
        XCTAssertFalse(vm.tokens.isEmpty, "The unfiltered list did load")
    }

    // MARK: - Destination picker publishes before providers return

    func testDestinationPickerPublishesLocalListBeforeProvidersReturn() async throws {
        let novel = meta("NOVL", contract: "0x000000000000000000000000000000000000abcd")
        let provider = GatedDestinationTokenProvider(
            bucket: DestinationTokenBucket(chain: .ethereum, tokens: [novel], uniqueIds: [novel.uniqueId])
        )
        let registry = DestinationTokenRegistry()
        registry.register(provider)

        SwapTokenListCache.shared.setCached([meta("USDC")], for: .ethereum)

        let vm = SwapCoinSelectionViewModel(
            vault: makeVault(),
            selectedCoin: makeCoin("ETH", isNative: true),
            isDestination: true,
            registry: registry
        )

        let fetchTask = Task { await vm.fetchCoins(chain: .ethereum, forceRefresh: true) }
        defer { provider.release() }

        // The local list must publish while the provider is still gated.
        try await waitUntil("local list published") { !vm.filteredTokens.isEmpty }
        XCTAssertFalse(vm.isLoading, "The first (local) publish clears the loading state")
        XCTAssertTrue(vm.filteredTokens.contains { $0.ticker == "ETH" }, "Curated native must be in the local list")
        XCTAssertTrue(vm.filteredTokens.contains { $0.ticker == "USDC" }, "Cached external token must be in the local list")
        XCTAssertFalse(vm.filteredTokens.contains { $0.ticker == "NOVL" }, "Provider tokens only land on the enriched publish")

        provider.release()
        await fetchTask.value

        XCTAssertTrue(vm.filteredTokens.contains { $0.ticker == "NOVL" }, "Provider token must append once the registry returns")
        XCTAssertTrue(vm.filteredTokens.contains { $0.ticker == "USDC" }, "Enriched publish keeps the local tokens")
    }

    func testDestinationPickerEnrichedPublishPreservesTypedQuery() async throws {
        let novel = meta("NOVL", contract: "0x000000000000000000000000000000000000abcd")
        let provider = GatedDestinationTokenProvider(
            bucket: DestinationTokenBucket(chain: .ethereum, tokens: [novel], uniqueIds: [novel.uniqueId])
        )
        let registry = DestinationTokenRegistry()
        registry.register(provider)

        SwapTokenListCache.shared.setCached([meta("USDC")], for: .ethereum)

        let vm = SwapCoinSelectionViewModel(
            vault: makeVault(),
            selectedCoin: makeCoin("ETH", isNative: true),
            isDestination: true,
            registry: registry
        )

        let fetchTask = Task { await vm.fetchCoins(chain: .ethereum, forceRefresh: true) }
        defer { provider.release() }

        try await waitUntil("local list published") { !vm.filteredTokens.isEmpty }

        // User types while the provider refresh is still in flight.
        vm.searchText = "usdc"

        provider.release()
        await fetchTask.value

        XCTAssertEqual(vm.filteredTokens.map { $0.ticker }, ["USDC"], "Enriched publish must re-apply the typed query")
    }

    func testSourcePickerIgnoresDestinationProviders() async throws {
        // The gate stays closed while the fetch runs — if the source-side
        // picker consulted the registry, the bounded wait below would fail the
        // test, and the deferred release keeps the fetch from hanging forever.
        let novel = meta("NOVL", contract: "0x000000000000000000000000000000000000abcd")
        let provider = GatedDestinationTokenProvider(
            bucket: DestinationTokenBucket(chain: .ethereum, tokens: [novel], uniqueIds: [novel.uniqueId])
        )
        let registry = DestinationTokenRegistry()
        registry.register(provider)

        SwapTokenListCache.shared.setCached([meta("USDC")], for: .ethereum)

        let vm = SwapCoinSelectionViewModel(
            vault: makeVault(),
            selectedCoin: makeCoin("ETH", isNative: true),
            isDestination: false,
            registry: registry
        )

        let fetchTask = Task { await vm.fetchCoins(chain: .ethereum, forceRefresh: true) }
        defer { provider.release() }

        try await waitUntil("source-side fetch to publish without the registry") { !vm.filteredTokens.isEmpty }

        XCTAssertTrue(vm.filteredTokens.contains { $0.ticker == "ETH" })
        XCTAssertTrue(vm.filteredTokens.contains { $0.ticker == "USDC" })
        XCTAssertFalse(vm.filteredTokens.contains { $0.ticker == "NOVL" }, "Source side must not pull destination-provider tokens")
        XCTAssertFalse(provider.wasQueried, "Source side must not consult the destination registry")
        await fetchTask.value
    }

    // MARK: - Cold cache (no SwapTokenListCache entry)

    func testColdCacheDestinationPublishesLocalListBeforeProvidersReturn() async throws {
        // Bitcoin's external-token fetch is a synchronous empty list (no
        // 1inch/Jupiter source), so the cold path is deterministic in tests:
        // the only slow hop left is the gated registry inside the full merge.
        let novel = meta("NOVL", chain: .bitcoin, contract: "0x000000000000000000000000000000000000abcd")
        let provider = GatedDestinationTokenProvider(
            bucket: DestinationTokenBucket(chain: .bitcoin, tokens: [novel], uniqueIds: [novel.uniqueId])
        )
        let registry = DestinationTokenRegistry()
        registry.register(provider)

        XCTAssertNil(SwapTokenListCache.shared.cached(for: .bitcoin), "Precondition: cold cache")

        let vm = SwapCoinSelectionViewModel(
            vault: makeVault(),
            selectedCoin: makeCoin("ETH", isNative: true),
            isDestination: true,
            registry: registry
        )

        let fetchTask = Task { await vm.fetchCoins(chain: .bitcoin, forceRefresh: true) }
        defer { provider.release() }

        // The curated-native + vault-coin list must paint while the registry
        // is still gated — a cold cache must not block the first publish.
        try await waitUntil("cold-cache local list published") { !vm.filteredTokens.isEmpty }
        XCTAssertFalse(vm.isLoading, "The local publish clears the cold-load spinner")
        XCTAssertTrue(vm.filteredTokens.contains { $0.ticker == "BTC" }, "Curated native must be in the local list")
        XCTAssertFalse(vm.filteredTokens.contains { $0.ticker == "NOVL" }, "Provider tokens only land on the enriched publish")

        provider.release()
        await fetchTask.value

        XCTAssertTrue(vm.filteredTokens.contains { $0.ticker == "NOVL" }, "Provider token must append once the registry returns")
    }

    func testColdCacheSourcePickerPublishesOnceWithoutRegistry() async throws {
        let novel = meta("NOVL", chain: .bitcoin, contract: "0x000000000000000000000000000000000000abcd")
        let provider = GatedDestinationTokenProvider(
            bucket: DestinationTokenBucket(chain: .bitcoin, tokens: [novel], uniqueIds: [novel.uniqueId])
        )
        let registry = DestinationTokenRegistry()
        registry.register(provider)

        XCTAssertNil(SwapTokenListCache.shared.cached(for: .bitcoin), "Precondition: cold cache")

        let vm = SwapCoinSelectionViewModel(
            vault: makeVault(),
            selectedCoin: makeCoin("ETH", isNative: true),
            isDestination: false,
            registry: registry
        )
        XCTAssertTrue(vm.isLoading, "Source-side cold open starts on the spinner")

        let fetchTask = Task { await vm.fetchCoins(chain: .bitcoin, forceRefresh: true) }
        defer { provider.release() }

        try await waitUntil("source-side cold fetch to publish") { !vm.filteredTokens.isEmpty }

        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(vm.filteredTokens.contains { $0.ticker == "BTC" })
        XCTAssertFalse(vm.filteredTokens.contains { $0.ticker == "NOVL" }, "Source side must not pull destination-provider tokens")
        XCTAssertFalse(provider.wasQueried, "Source side must not consult the destination registry")
        await fetchTask.value
    }

    // MARK: - Helpers

    private func makeLogic() -> SwapCoinSelectionLogic {
        SwapCoinSelectionLogic(
            vault: makeVault(),
            selectedCoin: makeCoin("ETH", isNative: true),
            isDestination: true,
            registry: DestinationTokenRegistry()
        )
    }

    private func makeVault() -> Vault {
        Vault(
            name: "Test Vault",
            signers: [],
            pubKeyECDSA: "test-pub-ecdsa",
            pubKeyEdDSA: "test-pub-eddsa",
            keyshares: [],
            localPartyID: "iPhone-12345",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
    }

    private func makeCoin(_ ticker: String, isNative: Bool = false) -> Coin {
        Coin(asset: meta(ticker, isNative: isNative), address: "test-address-\(ticker)", hexPublicKey: "")
    }

    private func meta(_ ticker: String, isNative: Bool = false, chain: Chain = .ethereum, contract: String = "") -> CoinMeta {
        CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "",
            decimals: isNative ? 18 : 6,
            priceProviderId: "",
            contractAddress: isNative ? "" : contract.isEmpty ? "0x\(ticker.lowercased())" : contract,
            isNativeToken: isNative
        )
    }

    private struct WaitTimeout: Error {}

    /// Polls `condition`, throwing on timeout so the calling test exits
    /// immediately (its `defer { provider.release() }` then unblocks any
    /// still-gated fetch) instead of running follow-up awaits that could hang.
    private func waitUntil(
        _ what: String,
        timeout: TimeInterval = 5,
        condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for \(what)")
                throw WaitTimeout()
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

// MARK: - GatedDestinationTokenProvider

/// A `DestinationTokenProvider` that suspends inside `tokens(for:)` until the
/// test releases it — simulating a slow remote catalog refresh so tests can
/// assert what the picker publishes while the fetch is still in flight.
@MainActor
private final class GatedDestinationTokenProvider: DestinationTokenProvider {
    let providerKind = "gatedTestProvider"
    private(set) var wasQueried = false
    private var released = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private let bucket: DestinationTokenBucket

    init(bucket: DestinationTokenBucket) {
        self.bucket = bucket
    }

    func tokens(for chain: Chain, forceRefresh _: Bool) async -> DestinationTokenBucket {
        wasQueried = true
        if !released {
            await withCheckedContinuation { continuations.append($0) }
        }
        return chain == bucket.chain ? bucket : .empty(chain: chain)
    }

    func release() {
        released = true
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }
}
