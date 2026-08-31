//
//  CustomTokenViewModelTests.swift
//  VultisigAppTests
//
//  Verifies that the custom-token search area has a single source of truth:
//  success and failure are mutually exclusive, clearing/editing the field resets it,
//  and a superseded in-flight lookup can never overwrite newer state.
//

import XCTest
@testable import VultisigApp

@MainActor
final class CustomTokenViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeCoin(ticker: String = "USDC", contract: String = "0xabc") -> CoinMeta {
        CoinMeta(
            chain: .ethereum,
            ticker: ticker,
            logo: "",
            decimals: 6,
            priceProviderId: "",
            contractAddress: contract,
            isNativeToken: false
        )
    }

    private func makeViewModel(resolver: CustomTokenResolver) -> CustomTokenViewModel {
        CustomTokenViewModel(vault: Vault(name: "test"), chain: .ethereum, resolver: resolver)
    }

    // MARK: - Mutual exclusivity

    /// Finding a token and then searching one that does not resolve must REPLACE the
    /// found result with the error — never show both (the reported bug).
    func testFoundThenInvalidReplacesFoundResult() async {
        let coin = makeCoin()
        var resolvesToToken = true
        let resolver = MockCustomTokenResolver(
            validateHandler: { _ in true },
            fetchInfoHandler: { _ in resolvesToToken ? coin : nil }
        )
        let viewModel = makeViewModel(resolver: resolver)
        viewModel.contractAddress = "0xabc"
        viewModel.validateAddress("0xabc")

        await viewModel.search().value
        XCTAssertEqual(viewModel.searchState, .found(coin))

        resolvesToToken = false
        await viewModel.search().value

        guard case .invalid = viewModel.searchState else {
            return XCTFail("expected .invalid, got \(viewModel.searchState)")
        }
        XCTAssertNotEqual(viewModel.searchState, .found(coin), "found result must not linger")
    }

    /// A successful lookup after a prior failure must clear the error.
    func testSuccessClearsPriorError() async {
        let coin = makeCoin()
        var resolvesToToken = false
        let resolver = MockCustomTokenResolver(
            validateHandler: { _ in true },
            fetchInfoHandler: { _ in resolvesToToken ? coin : nil }
        )
        let viewModel = makeViewModel(resolver: resolver)
        viewModel.contractAddress = "0xabc"
        viewModel.validateAddress("0xabc")

        await viewModel.search().value
        guard case .invalid = viewModel.searchState else {
            return XCTFail("expected .invalid first, got \(viewModel.searchState)")
        }

        resolvesToToken = true
        await viewModel.search().value
        XCTAssertEqual(viewModel.searchState, .found(coin))
    }

    /// Clearing the input field resets the search area to idle so nothing lingers.
    func testEmptyInputResetsToIdle() async {
        let coin = makeCoin()
        let resolver = MockCustomTokenResolver(
            validateHandler: { !$0.isEmpty },
            fetchInfoHandler: { _ in coin }
        )
        let viewModel = makeViewModel(resolver: resolver)
        viewModel.contractAddress = "0xabc"
        viewModel.validateAddress("0xabc")

        await viewModel.search().value
        XCTAssertEqual(viewModel.searchState, .found(coin))

        viewModel.contractAddress = ""
        viewModel.validateAddress("")
        XCTAssertEqual(viewModel.searchState, .idle)
    }

    // MARK: - Validation guard

    func testResolverFactorySupportsOnlyResolvableChains() {
        let expected: Set<Chain> = [
            .thorChain,
            .solana,
            .ethereum,
            .avalanche,
            .base,
            .blast,
            .arbitrum,
            .polygon,
            .polygonV2,
            .optimism,
            .bscChain,
            .cardano,
            .cronosChain,
            .sui,
            .zksync,
            .ton,
            .terra,
            .terraClassic,
            .ripple,
            .tron,
            .ethereumSepolia,
            .mantle,
            .hyperliquid,
            .sei,
            .robinhood
        ]

        let supported = Set(Chain.allCases.filter { CustomTokenResolverFactory.supports(chain: $0) })

        XCTAssertEqual(supported, expected)
    }

    /// An input that fails address validation short-circuits to an error without a
    /// network call and replaces any prior state.
    func testInvalidAddressGuardProducesInvalidState() async {
        let resolver = MockCustomTokenResolver(
            validateHandler: { _ in false },
            fetchInfoHandler: { _ in
                XCTFail("resolver must not be called for an invalid address")
                return nil
            }
        )
        let viewModel = makeViewModel(resolver: resolver)
        viewModel.contractAddress = "not-an-address"
        viewModel.validateAddress("not-an-address")

        await viewModel.search().value
        guard case .invalid = viewModel.searchState else {
            return XCTFail("expected .invalid, got \(viewModel.searchState)")
        }
    }

    // MARK: - Superseded in-flight lookups (cancel-and-restart)

    /// A lookup that finishes *after* the user clears the field must be discarded — its
    /// stale result may not repopulate the now-empty (idle) search area.
    func testClearingFieldDuringFetchDiscardsStaleResult() async {
        let viewModel = await runStaleLookup { viewModel in
            viewModel.contractAddress = ""
            viewModel.validateAddress("")
        }
        XCTAssertEqual(viewModel.searchState, .idle)
    }

    /// Editing the address to a *different* value mid-lookup must likewise discard the
    /// old lookup — its result was for the previous address.
    func testEditingAddressDuringFetchDiscardsStaleResult() async {
        let viewModel = await runStaleLookup { viewModel in
            viewModel.contractAddress = "0xdef"
            viewModel.validateAddress("0xdef")
        }
        XCTAssertEqual(viewModel.searchState, .idle)
    }

    /// A search whose task is cancelled before it even begins (a newer search
    /// superseded it while it was still queued — task scheduling is not FIFO) must not
    /// mutate state, in particular must not leave the UI stuck in `.loading`.
    func testCancelledSearchBeforeStartDoesNotGetStuckLoading() async {
        let coin = makeCoin()
        let resolver = MockCustomTokenResolver(
            validateHandler: { _ in true },
            fetchInfoHandler: { _ in coin }
        )
        let viewModel = makeViewModel(resolver: resolver)
        viewModel.contractAddress = "0xabc"
        viewModel.validateAddress("0xabc")

        let task = viewModel.search()
        task.cancel() // superseded before the task body runs
        await task.value

        XCTAssertNotEqual(viewModel.searchState, .loading, "a superseded search must not stick in loading")
        XCTAssertEqual(viewModel.searchState, .idle)
    }

    // MARK: - saving a custom token must not drop a held DeFi position

    /// The custom-token screen is the other exit from the token-selection sheet
    /// and saves the same shared selection. That selection is seeded by chain
    /// detail's periodic refresh, so it can predate a DeFi receipt discovery has
    /// since added — and the sheet never renders receipts, so nothing puts it
    /// back. Adding an unrelated custom token must not delete the position.
    func testAddingACustomTokenKeepsAHeldDefiPosition() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let vault = TestStore.makeVault(pubKey: "custom-token-defi")
        let rune = Coin(asset: TokensStore.rune, address: "thoraddr", hexPublicKey: "pub")
        let receipt = Coin(asset: TokensStore.ybrune, address: "thoraddr", hexPublicKey: "pub")
        vault.coins = [rune, receipt]
        Storage.shared.insert([rune, receipt])

        let custom = CoinMeta(
            chain: .thorChain,
            ticker: "LQDY",
            logo: "lqdy",
            decimals: 8,
            priceProviderId: "",
            contractAddress: "thor.lqdy",
            isNativeToken: false
        )
        let resolver = MockCustomTokenResolver(
            validateHandler: { _ in true },
            fetchInfoHandler: { _ in custom }
        )
        let viewModel = CustomTokenViewModel(vault: vault, chain: .thorChain, resolver: resolver)
        viewModel.contractAddress = "thor.lqdy"
        viewModel.validateAddress("thor.lqdy")
        await viewModel.search().value

        // The stale selection: RUNE only — the receipt is missing from it, and
        // the sheet has no row that could put it back.
        let coinSelectionViewModel = CoinSelectionViewModel()
        coinSelectionViewModel.selection = [TokensStore.rune]

        _ = await viewModel.saveAssets(coinSelectionViewModel: coinSelectionViewModel)

        XCTAssertTrue(vault.coins.contains { $0.uniqueId == receipt.uniqueId },
                      "Adding a custom token must not delete an unrelated held DeFi position")
        XCTAssertFalse(vault.hiddenTokens.contains { $0.ticker.uppercased() == "YBRUNE" },
                       "…nor suppress it from every later list")
    }

    /// Drives a search that suspends inside the resolver, runs `interrupt` while it is
    /// in flight, then releases the lookup and asserts the stale result was discarded.
    @discardableResult
    private func runStaleLookup(
        interrupt: (CustomTokenViewModel) -> Void
    ) async -> CustomTokenViewModel {
        let coin = makeCoin()
        let entered = TestGate()
        let release = TestGate()
        let resolver = MockCustomTokenResolver(
            validateHandler: { !$0.isEmpty },
            fetchInfoHandler: { _ in
                await entered.open()
                await release.wait()
                return coin
            }
        )
        let viewModel = makeViewModel(resolver: resolver)
        viewModel.contractAddress = "0xabc"
        viewModel.validateAddress("0xabc")

        let task = viewModel.search()
        await entered.wait()
        XCTAssertEqual(viewModel.searchState, .loading)

        interrupt(viewModel)
        XCTAssertEqual(viewModel.searchState, .idle)

        await release.open()
        await task.value
        return viewModel
    }
}

// MARK: - Test doubles

/// A one-shot async gate: `wait()` suspends until `open()` is called (and returns
/// immediately once opened). Lets a test deterministically pause a resolver mid-lookup.
private actor TestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        guard !isOpen else { return }
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private final class MockCustomTokenResolver: CustomTokenResolver, @unchecked Sendable {
    let requiresVaultNativeCoin: Bool
    var validateHandler: (String) -> Bool
    var fetchInfoHandler: (String) async throws -> CoinMeta?

    init(
        requiresVaultNativeCoin: Bool = false,
        validateHandler: @escaping (String) -> Bool,
        fetchInfoHandler: @escaping (String) async throws -> CoinMeta?
    ) {
        self.requiresVaultNativeCoin = requiresVaultNativeCoin
        self.validateHandler = validateHandler
        self.fetchInfoHandler = fetchInfoHandler
    }

    func fetchInfo(contract: String) async throws -> CoinMeta? {
        try await fetchInfoHandler(contract)
    }

    func validate(_ address: String) -> Bool {
        validateHandler(address)
    }
}
