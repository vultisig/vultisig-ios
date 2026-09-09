//
//  SwapVerifyRouteSelectionTests.swift
//  VultisigAppTests
//
//  The verify screen re-quotes every 60s and must re-resolve a manual route pick
//  against the fresh candidate set rather than installing the auto winner.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SwapVerifyRouteSelectionTests: XCTestCase {
    private var storeToken: TestContextToken?

    override func setUpWithError() throws {
        storeToken = try TestStore.installInMemoryContainer()
    }

    override func tearDown() {
        TestStore.restore(storeToken)
        storeToken = nil
    }

    func testRefreshKeepsThePickedRouteAndRepointsIt() async {
        let best = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "300000000"))
        let stale = SwapQuote.oneinch(makeEVMQuote(dstAmount: "100000000"), fee: nil)
        let fresh = SwapQuote.oneinch(makeEVMQuote(dstAmount: "123456789"), fee: nil)
        XCTAssertNotEqual(stale, fresh, "Fixture must differ by payload")

        let vm = makeVM(
            transaction: makeTransaction(quote: stale, pickedProvider: .oneinch(.arbitrum), fromChain: .arbitrum),
            refreshed: makeResult(best: best, allQuotes: [best, fresh])
        )
        vm.isAmountCorrect = true
        vm.isFeeCorrect = true

        await vm.refreshData(vault: makeVault())

        XCTAssertEqual(vm.transaction.quote, fresh, "The refresh must keep the picked route, on fresh numbers")
        XCTAssertEqual(vm.transaction.selectedProvider, .oneinch(.arbitrum), "…and keep it pinned for the next refresh")
        XCTAssertNil(vm.routeSelectionNotice, "Nothing was substituted, so there is nothing to say")
        XCTAssertTrue(vm.isAmountCorrect, "Confirmations stand when the route did not change")
        XCTAssertTrue(vm.isFeeCorrect)
    }

    func testRefreshSubstitutesAutoAndResetsConfirmationsWhenRouteGone() async {
        let best = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "300000000"))
        let stale = SwapQuote.oneinch(makeEVMQuote(dstAmount: "100000000"), fee: nil)

        let vm = makeVM(
            transaction: makeTransaction(quote: stale, pickedProvider: .oneinch(.ethereum)),
            refreshed: makeResult(best: best, allQuotes: [best])
        )
        vm.isAmountCorrect = true
        vm.isFeeCorrect = true
        vm.isApproveCorrect = true

        await vm.refreshData(vault: makeVault())

        XCTAssertEqual(vm.transaction.quote, best, "With the picked route gone, the auto winner takes over")
        XCTAssertNil(vm.transaction.selectedProvider, "The pin is released so later refreshes follow Auto")
        XCTAssertEqual(
            vm.routeSelectionNotice,
            "swapRouteUnavailableResetToAuto".localized,
            "Swapping the route under a confirmed order must never be silent"
        )
        XCTAssertFalse(vm.isAmountCorrect, "Confirmations were given for a route that is gone")
        XCTAssertFalse(vm.isFeeCorrect)
        XCTAssertFalse(vm.isApproveCorrect)
    }

    func testRefreshOnAutoFollowsTheFreshWinner() async {
        let previousBest = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "300000000"))
        let newBest = SwapQuote.oneinch(makeEVMQuote(dstAmount: "900000000"), fee: nil)

        // Auto must stay free to change winner between refreshes.
        let vm = makeVM(
            transaction: makeTransaction(quote: previousBest, pickedProvider: nil),
            refreshed: makeResult(best: newBest, allQuotes: [newBest, previousBest])
        )
        vm.isAmountCorrect = true

        await vm.refreshData(vault: makeVault())

        XCTAssertEqual(vm.transaction.quote, newBest, "Auto follows the fresh winner")
        XCTAssertNil(vm.transaction.selectedProvider)
        XCTAssertNil(vm.routeSelectionNotice, "Auto changing winner is not a substitution")
        XCTAssertTrue(vm.isAmountCorrect, "The Auto path must not disturb the confirmations")
    }

    func testTimerRefreshDoesNotOverlapTimerOrExplicitRefetch() async {
        let quote = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "100000000"))
        let gate = RefreshRequestGate()
        let vm = SwapVerifyViewModel(
            transaction: makeTransaction(quote: quote, pickedProvider: nil),
            interactor: RouteSelectionStubInteractor(
                refreshed: makeResult(best: quote, allQuotes: [quote]),
                beforeFetch: { try await gate.wait() }
            )
        )
        let vault = makeVault()
        vm.timer = 1
        let refresh = Task { await vm.updateTimer(vault: vault) }
        await fulfillment(of: [gate.started], timeout: 2)

        XCTAssertTrue(vm.isLoadingFees)
        XCTAssertEqual(vm.timer, 0)
        await vm.updateTimer(vault: vault)
        await vm.refreshData(vault: vault)
        XCTAssertEqual(gate.calls, 1, "Timer ticks and explicit refetches must not overlap the pending request")
        XCTAssertTrue(vm.isLoadingFees, "A duplicate refresh must not clear the active request's loading state")
        XCTAssertEqual(vm.timer, 0, "The countdown pauses until the refresh completes")

        gate.finish()
        await refresh.value
        XCTAssertFalse(vm.isLoadingFees)
        XCTAssertEqual(vm.timer, 59)
    }

    func testRefreshStaysLoadingUntilFeeFetchCompletes() async {
        let stale = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "100000000"))
        let fresh = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "200000000"))
        let gate = RefreshRequestGate()
        let vm = SwapVerifyViewModel(
            transaction: makeTransaction(quote: stale, pickedProvider: nil),
            interactor: RouteSelectionStubInteractor(
                refreshed: makeResult(best: fresh, allQuotes: [fresh]),
                beforeFees: { try await gate.wait() }
            )
        )
        let refresh = Task { await vm.refreshData(vault: makeVault()) }
        await fulfillment(of: [gate.started], timeout: 2)

        XCTAssertTrue(vm.isLoadingFees, "Receiving the quote must not dismiss loading while fees are pending")
        XCTAssertEqual(vm.transaction.quote, stale)
        gate.finish()
        await refresh.value
        XCTAssertFalse(vm.isLoadingFees)
        XCTAssertEqual(vm.transaction.quote, fresh)
    }

    func testFailedRefreshClearsLoadingAndRestartsCountdown() async {
        let quote = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "100000000"))
        let gate = RefreshRequestGate()
        let vm = SwapVerifyViewModel(
            transaction: makeTransaction(quote: quote, pickedProvider: nil),
            interactor: RouteSelectionStubInteractor(
                refreshed: makeResult(best: quote, allQuotes: [quote]),
                beforeFetch: { try await gate.wait() }
            )
        )
        vm.timer = 1
        let refresh = Task { await vm.updateTimer(vault: makeVault()) }
        await fulfillment(of: [gate.started], timeout: 2)
        XCTAssertTrue(vm.isLoadingFees)

        gate.finish(error: URLError(.timedOut))
        await refresh.value
        XCTAssertFalse(vm.isLoadingFees)
        XCTAssertEqual(vm.timer, 59)
        XCTAssertEqual(vm.transaction.quote, quote)
    }

    // MARK: - Fixtures

    private func makeVM(transaction: SwapTransaction, refreshed: SwapQuoteResult) -> SwapVerifyViewModel {
        SwapVerifyViewModel(
            transaction: transaction,
            interactor: RouteSelectionStubInteractor(refreshed: refreshed)
        )
    }

    private func makeResult(best: SwapQuote, allQuotes: [SwapQuote]) -> SwapQuoteResult {
        SwapQuoteResult(quote: best, allQuotes: allQuotes, vultDiscountBps: 0, referralDiscountBps: 0)
    }

    private func makeTransaction(
        quote: SwapQuote,
        pickedProvider: SwapProvider?,
        fromChain: Chain = .ethereum
    ) -> SwapTransaction {
        let eth = makeCoin(fromChain, ticker: "ETH", balance: "5000000000000000000")
        let btc = makeCoin(.bitcoin, ticker: "BTC")
        return SwapTransaction(
            fromCoin: eth,
            toCoin: btc,
            fromAmount: 1,
            kind: .market(quote),
            gas: .zero,
            gasLimit: .zero,
            thorchainFee: .zero,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: eth,
            advancedSettings: .default,
            selectedProvider: pickedProvider
        )
    }

    private func makeVault() -> Vault {
        Vault(
            name: "Test Vault", signers: [], pubKeyECDSA: "e", pubKeyEdDSA: "d",
            keyshares: [], localPartyID: "iPhone", hexChainCode: "hex",
            resharePrefix: nil, libType: .DKLS
        )
    }

    private func makeCoin(_ chain: Chain, ticker: String, balance: String = "0") -> Coin {
        let meta = CoinMeta.make(chain: chain, ticker: ticker, decimals: 8, isNativeToken: true)
        let coin = Coin(asset: meta, address: "test-address-\(ticker)", hexPublicKey: "")
        coin.rawBalance = balance
        return coin
    }

    private func makeThorQuote(expectedAmountOut: String) -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: expectedAmountOut,
            expiry: 0,
            fees: Fees(affiliate: "0", asset: "RUNE", outbound: "0", total: "0", liquidity: nil, slippageBps: nil, totalBps: nil),
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

    private func makeEVMQuote(dstAmount: String) -> EVMQuote {
        EVMQuote(
            dstAmount: dstAmount,
            tx: EVMQuote.Transaction(
                from: "0xfrom",
                to: "0xto",
                data: "0x",
                value: "0",
                gasPrice: "0",
                gas: 0
            )
        )
    }
}

// swiftlint:disable async_without_await unused_parameter

/// One fixed refreshed candidate set; everything else is a no-op stub.
private struct RouteSelectionStubInteractor: SwapInteractor {
    let refreshed: SwapQuoteResult
    var beforeFetch: (() async throws -> Void)? = nil
    var beforeFees: (() async throws -> Void)? = nil

    func fetchQuote(
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        vault: Vault,
        referredCode: String,
        slippageBps: Int?,
        recipientAddress: String?
    ) async throws -> SwapQuoteResult? {
        try await beforeFetch?()
        return refreshed
    }

    func fetchChainSpecific(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmount: Decimal,
        quote: SwapQuote?
    ) async throws -> BlockChainSpecific {
        try await beforeFees?()
        return .Cosmos(accountNumber: 0, sequence: 0, gas: 0, transactionType: 0, ibcDenomTrace: nil, gasLimit: nil)
    }

    func computeThorchainFee(
        chainSpecific: BlockChainSpecific,
        fromCoin: Coin,
        fromAmount: Decimal,
        vault: Vault
    ) async throws -> BigInt {
        .zero
    }

    func assertSourceChainNotHalted(transaction: SwapTransaction) async throws {}

    func buildSwapKeysignPayload(transaction: SwapTransaction, vault: Vault) async throws -> KeysignPayload {
        throw CancellationError()
    }

    func updateBalance(for coin: Coin) async {}

    func warmDiscountTier(for vault: Vault) async {}
}

// swiftlint:enable async_without_await unused_parameter

@MainActor
private final class RefreshRequestGate {
    let started = XCTestExpectation(description: "Refresh reached the delayed request")
    private(set) var calls = 0
    private var continuation: CheckedContinuation<Void, Error>?

    func wait() async throws {
        calls += 1
        // Let accidental overlapping calls finish so the test can assert the
        // wrong count/loading state without leaving a second task suspended.
        guard calls == 1 else { return }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }

    func finish(error: Error? = nil) {
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}
