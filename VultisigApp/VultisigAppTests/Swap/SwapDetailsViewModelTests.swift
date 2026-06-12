//
//  SwapDetailsViewModelTests.swift
//  VultisigAppTests
//
//  Covers the three display-layer quote UX behaviours and the signing guardrail:
//   1. The indicative "to" amount is display-only and can never satisfy
//      validation — `validateForm()` still requires a firm `quote`.
//   2. Stale-while-revalidate skeleton gating (`showsQuoteSkeleton`): skeleton
//      only on the first quote of a pair, not on refreshes that have a prior
//      quote, and never across a pair change.
//   3. The immediate fetch path (percentage / paste) skips the keystroke
//      debounce while free typing stays debounced.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SwapDetailsViewModelTests: XCTestCase {

    // MARK: - Item 1: indicative value is display-only (signing guardrail)

    func testValidateFormFailsWhenOnlyIndicativeAmountPresentAndQuoteNil() {
        let vm = makeVM()
        vm.fromCoin = makeCoin(.ethereum, ticker: "ETH", balance: "5000000000000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"
        // No firm quote — only the display-layer indicative could exist.
        vm.quote = nil

        XCTAssertFalse(
            vm.validateForm(),
            "validateForm must require a firm quote; the indicative value must never satisfy it"
        )
    }

    func testMakeTransactionReturnsNilWhenQuoteNil() {
        let vm = makeVM()
        vm.fromCoin = makeCoin(.ethereum, ticker: "ETH", balance: "5000000000000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"
        vm.quote = nil

        XCTAssertNil(vm.makeTransaction(), "makeTransaction must never materialise without a firm quote")
    }

    func testIndicativeReturnsNilForNonPositiveAmount() {
        let from = makeCoin(.ethereum, ticker: "ETH")
        let to = makeCoin(.bitcoin, ticker: "BTC")
        XCTAssertNil(SwapCryptoLogic.toAmountIndicative(fromCoin: from, toCoin: to, fromAmount: ""))
        XCTAssertNil(SwapCryptoLogic.toAmountIndicative(fromCoin: from, toCoin: to, fromAmount: "0"))
    }

    // MARK: - Item 2: stale-while-revalidate skeleton gating

    func testFirstQuoteForPairShowsSkeleton() async {
        let interactor = MockSwapInteractor(quote: .thorchain(makeThorQuote(expectedAmountOut: "100000000")))
        let vm = makeVM(interactor: interactor)
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"

        // First fetch: no prior quote → leading-edge skeleton should be on.
        vm.updateFromAmount(vault: makeVault(), referredCode: "", immediate: true)
        XCTAssertTrue(vm.showsQuoteSkeleton, "First quote of a pair must show the skeleton")

        await vm.waitForQuoteTask()
        XCTAssertNotNil(vm.quote)
        XCTAssertFalse(vm.showsQuoteSkeleton, "Skeleton must clear once the firm quote lands")
    }

    func testRefreshWithPriorQuoteDoesNotShowSkeleton() async {
        let interactor = MockSwapInteractor(quote: .thorchain(makeThorQuote(expectedAmountOut: "100000000")))
        let vm = makeVM(interactor: interactor)
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"

        // Land a firm quote first.
        vm.updateFromAmount(vault: makeVault(), referredCode: "", immediate: true)
        await vm.waitForQuoteTask()
        XCTAssertNotNil(vm.quote)

        // Auto-refresh on the same pair: the prior quote stays, so no skeleton.
        vm.refreshData(vault: makeVault(), referredCode: "")
        XCTAssertTrue(vm.isLoadingQuotes, "A refresh is in flight")
        XCTAssertFalse(
            vm.showsQuoteSkeleton,
            "Stale-while-revalidate: a refresh with a prior quote must not blank to skeleton"
        )
        await vm.waitForQuoteTask()
    }

    func testAmountChangeClearsStaleQuoteAndShowsSkeleton() async {
        let interactor = MockSwapInteractor(quote: .thorchain(makeThorQuote(expectedAmountOut: "100000000")))
        let vm = makeVM(interactor: interactor)
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"

        // Land a firm quote first.
        vm.updateFromAmount(vault: makeVault(), referredCode: "", immediate: true)
        await vm.waitForQuoteTask()
        XCTAssertNotNil(vm.quote)

        // Editing the amount (same pair) is NOT a silent refresh: the prior
        // quote belongs to the old amount, so it must clear immediately so the
        // "to" field falls back to the indicative estimate and the summary
        // shows its skeleton — stale-while-revalidate is for auto-refresh only.
        vm.fromAmount = "2"
        vm.updateFromAmount(vault: makeVault(), referredCode: "", immediate: true)
        XCTAssertNil(vm.quote, "Quote must clear on an amount change")
        XCTAssertTrue(vm.showsQuoteSkeleton, "An amount change must show the skeleton, not the stale summary")
        await vm.waitForQuoteTask()
    }

    func testPairChangeClearsStaleQuoteAndShowsSkeleton() async {
        let interactor = MockSwapInteractor(quote: .thorchain(makeThorQuote(expectedAmountOut: "100000000")))
        let vm = makeVM(interactor: interactor)
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"

        vm.updateFromAmount(vault: makeVault(), referredCode: "", immediate: true)
        await vm.waitForQuoteTask()
        XCTAssertNotNil(vm.quote)

        // Change the destination coin: the held quote is now meaningless and must
        // be cleared so a different-pair quote can't show through.
        vm.toCoin = makeCoin(.ethereum, ticker: "ETH")
        vm.updateFromAmount(vault: makeVault(), referredCode: "", immediate: true)
        XCTAssertNil(vm.quote, "Quote must be cleared on a pair change")
        XCTAssertTrue(vm.showsQuoteSkeleton, "A new pair with no prior quote must show the skeleton")
        await vm.waitForQuoteTask()
    }

    func testEmptyAmountClearsQuoteAndPair() async {
        let interactor = MockSwapInteractor(quote: .thorchain(makeThorQuote(expectedAmountOut: "100000000")))
        let vm = makeVM(interactor: interactor)
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"
        vm.updateFromAmount(vault: makeVault(), referredCode: "", immediate: true)
        await vm.waitForQuoteTask()
        XCTAssertNotNil(vm.quote)

        vm.fromAmount = ""
        vm.updateFromAmount(vault: makeVault(), referredCode: "")
        XCTAssertNil(vm.quote, "Emptying the amount must clear the quote")
        XCTAssertFalse(vm.showsQuoteSkeleton)
        XCTAssertFalse(vm.isLoadingQuotes)
    }

    // MARK: - Item 3: immediate vs debounced path

    func testImmediatePathResolvesWithoutDebounce() async {
        let interactor = MockSwapInteractor(quote: .thorchain(makeThorQuote(expectedAmountOut: "100000000")))
        let vm = makeVM(interactor: interactor)
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"

        let start = Date()
        vm.updateFromAmount(vault: makeVault(), referredCode: "", immediate: true)
        await vm.waitForQuoteTask()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertNotNil(vm.quote)
        XCTAssertEqual(interactor.fetchQuoteCallCount, 1)
        XCTAssertLessThan(elapsed, 0.25, "Immediate path must skip the 300ms debounce")
    }

    func testDebouncedPathWaitsForDebounceBeforeFetching() async {
        let interactor = MockSwapInteractor(quote: .thorchain(makeThorQuote(expectedAmountOut: "100000000")))
        let vm = makeVM(interactor: interactor)
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"

        // Default (typing) path is debounced — the network shouldn't be hit
        // before the debounce window elapses.
        vm.updateFromAmount(vault: makeVault(), referredCode: "")
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(interactor.fetchQuoteCallCount, 0, "Debounced path must not fetch before the debounce")

        await vm.waitForQuoteTask()
        XCTAssertEqual(interactor.fetchQuoteCallCount, 1, "Debounced path eventually fetches")
    }

    func testLeadingEdgeCancellationSupersedesPendingFetch() async {
        let interactor = MockSwapInteractor(quote: .thorchain(makeThorQuote(expectedAmountOut: "100000000")))
        let vm = makeVM(interactor: interactor)
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"

        // Start a debounced (typing) fetch, then supersede it immediately with a
        // percentage tap — the pending one must be cancelled, only one fetch runs.
        vm.updateFromAmount(vault: makeVault(), referredCode: "")
        vm.fromAmount = "2"
        vm.updateFromAmount(vault: makeVault(), referredCode: "", immediate: true)
        await vm.waitForQuoteTask()

        XCTAssertEqual(interactor.fetchQuoteCallCount, 1, "The superseded debounced fetch must be cancelled")
        XCTAssertNotNil(vm.quote)
    }

    // MARK: - Fixtures

    private func makeVM(interactor: SwapInteractor? = nil) -> SwapDetailsViewModel {
        SwapDetailsViewModel(interactor: interactor ?? MockSwapInteractor(quote: nil))
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

    private func makeCoin(_ chain: Chain, ticker: String, balance: String = "0") -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: 8, isNativeToken: true)
        let coin = Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
        coin.rawBalance = balance
        return coin
    }

    private func makeThorQuote(expectedAmountOut: String = "0") -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: expectedAmountOut,
            expiry: 0,
            fees: Fees(
                affiliate: "0",
                asset: "RUNE",
                outbound: "0",
                total: "0",
                liquidity: nil,
                slippageBps: nil,
                totalBps: nil
            ),
            inboundAddress: nil,
            inboundConfirmationBlocks: nil,
            inboundConfirmationSeconds: nil,
            memo: "memo",
            notes: "",
            outboundDelayBlocks: 0,
            outboundDelaySeconds: 0,
            recommendedMinAmountIn: "0",
            slippageBps: nil,
            totalSwapSeconds: nil,
            warning: "",
            router: nil,
            maxStreamingQuantity: nil
        )
    }
}

// MARK: - Test helpers

private extension SwapDetailsViewModel {
    /// Awaits the in-flight quote task so assertions run after it settles.
    /// Polls a short, bounded number of times to avoid coupling to internal task
    /// handles while keeping the test deterministic.
    func waitForQuoteTask() async {
        for _ in 0..<200 where isLoadingQuotes {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

// swiftlint:disable async_without_await unused_parameter

/// Minimal `SwapInteractor` mock: returns a fixed quote (or none) and records
/// how many times the quote fetch ran so the debounce/immediate paths can be
/// asserted. Fees resolve to zero so the happy path keeps the quote set.
@MainActor
private final class MockSwapInteractor: SwapInteractor {
    private let stubbedQuote: SwapQuote?
    private(set) var fetchQuoteCallCount = 0

    init(quote: SwapQuote?) {
        self.stubbedQuote = quote
    }

    func fetchQuote(
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        vault: Vault,
        referredCode: String,
        slippageBps: Int?,
        recipientAddress: String?
    ) async throws -> SwapQuoteResult? {
        fetchQuoteCallCount += 1
        guard let stubbedQuote else { return nil }
        return SwapQuoteResult(quote: stubbedQuote, vultDiscountBps: 0, referralDiscountBps: 0)
    }

    func isProviderSelectionUnlocked(for vault: Vault) async -> Bool { false }

    func fetchChainSpecific(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmount: Decimal,
        quote: SwapQuote?
    ) async throws -> BlockChainSpecific {
        .Cosmos(accountNumber: 0, sequence: 0, gas: 0, transactionType: 0, ibcDenomTrace: nil)
    }

    func computeThorchainFee(
        chainSpecific: BlockChainSpecific,
        fromCoin: Coin,
        fromAmount: Decimal,
        vault: Vault
    ) async throws -> BigInt {
        .zero
    }

    func buildSwapKeysignPayload(transaction: SwapTransaction, vault: Vault) async throws -> KeysignPayload {
        throw CancellationError()
    }

    func updateBalance(for coin: Coin) async {}

    func warmDiscountTier(for vault: Vault) async {}
}

// swiftlint:enable async_without_await unused_parameter
