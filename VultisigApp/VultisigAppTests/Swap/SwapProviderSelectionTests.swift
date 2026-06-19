//
//  SwapProviderSelectionTests.swift
//  VultisigAppTests
//
//  Covers the provider-selection feature:
//   1. Ranking — `SwapService.rankedQuotes` sorts best→worst by
//      `expectedNetToAmount`, and `selectBestQuote`'s winner is the rate-top
//      when no provider-preference band applies.
//   2. VM selection — `selectedQuote` drives the computed `quote`, a non-best
//      pick reaches the active quote (and therefore the verify/sign summary),
//      and every refresh resets the override back to Best.
//   3. The below-Silver invariant: provider selection is inert
//      (no list, best auto-selected) unless the gate is unlocked.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SwapProviderSelectionTests: XCTestCase {

    // MARK: - Item 1: ranking order

    func testRankedQuotesSortedByNetOutputDescending() {
        let toCoin = makeCoin(.bitcoin, ticker: "BTC")
        // Deliberately out of order on the wire so the sort is doing the work.
        let low = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "100000000"))      // 1.0 BTC
        let high = SwapQuote.thorchainChainnet(makeThorQuote(expectedAmountOut: "300000000")) // 3.0 BTC
        let mid = SwapQuote.thorchainStagenet(makeThorQuote(expectedAmountOut: "200000000"))  // 2.0 BTC

        let ranked = SwapService.rankedQuotes(quotes: [low, high, mid], toCoin: toCoin)

        XCTAssertEqual(ranked, [high, mid, low], "Ranked list must be sorted best→worst by net output")
    }

    func testRankedQuotesDropsUnrankableQuotes() {
        let toCoin = makeCoin(.bitcoin, ticker: "BTC")
        let good = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "100000000"))
        // Zero output can't be ranked (expectedNetToAmount returns nil).
        let unrankable = SwapQuote.thorchainChainnet(makeThorQuote(expectedAmountOut: "0"))

        let ranked = SwapService.rankedQuotes(quotes: [good, unrankable], toCoin: toCoin)

        XCTAssertEqual(ranked, [good], "Quotes without a comparable net amount must be dropped")
    }

    func testBestQuoteIsRateTopWhenNoPreferenceBandApplies() {
        let toCoin = makeCoin(.bitcoin, ticker: "BTC")
        // Two providers far apart on rate (outside the 1% preference band): the
        // larger net output must win regardless of provider priority.
        let oneInch = SwapQuote.oneinch(makeEVMQuote(dstAmount: "100000000"), fee: nil)
        let thor = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "300000000")) // 3.0 BTC

        let best = SwapService.selectBestQuote(quotes: [oneInch, thor], toCoin: toCoin)
        let ranked = SwapService.rankedQuotes(quotes: [oneInch, thor], toCoin: toCoin)

        XCTAssertEqual(best, thor, "The materially-better net output must be the winner")
        XCTAssertEqual(ranked.first, best, "The ranked top must equal the auto-selected winner here")
    }

    // MARK: - Item 2: VM selection carries into the active quote

    func testSelectedQuoteDrivesActiveQuote() async {
        let best = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "300000000"))
        let alt = SwapQuote.oneinch(makeEVMQuote(dstAmount: "100000000"), fee: nil)
        let vm = makeVM(best: best, allQuotes: [best, alt], providerSelectionUnlocked: true)
        await landQuotes(on: vm)

        XCTAssertEqual(vm.quote, best, "With no override, the active quote is Best")

        vm.selectProvider(alt)

        XCTAssertEqual(vm.selectedQuote, alt)
        XCTAssertEqual(vm.quote, alt, "A manual pick must become the active quote")
    }

    func testNonBestSelectionReachesTransaction() async {
        let best = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "300000000"))
        // Non-zero fee so `validateForm` (which requires `fee != .zero`) passes
        // and a real `SwapTransaction` materialises off the selected quote.
        let alt = SwapQuote.oneinch(makeEVMQuote(dstAmount: "100000000"), fee: BigInt(1_000))
        let vm = makeVM(best: best, allQuotes: [best, alt], providerSelectionUnlocked: true)
        vm.fromCoin = makeCoin(.ethereum, ticker: "ETH", balance: "5000000000000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"
        await landQuotes(on: vm)

        vm.selectProvider(alt)
        let transaction = vm.makeTransaction()

        XCTAssertNotNil(transaction, "Form should validate with a firm quote")
        XCTAssertEqual(transaction?.quote, alt, "The non-best pick must carry into the signed transaction")
    }

    func testRefreshResetsSelectionBackToBest() async {
        let best = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "300000000"))
        let alt = SwapQuote.oneinch(makeEVMQuote(dstAmount: "100000000"), fee: nil)
        let vm = makeVM(best: best, allQuotes: [best, alt], providerSelectionUnlocked: true)
        await landQuotes(on: vm)

        vm.selectProvider(alt)
        XCTAssertEqual(vm.quote, alt)

        // A fresh quote landing (same-pair refresh) must drop the manual override.
        await landQuotes(on: vm)
        XCTAssertNil(vm.selectedQuote, "A refresh must reset the manual override")
        XCTAssertEqual(vm.quote, best, "After a refresh the active quote re-defaults to Best")
    }

    func testEmptyAmountClearsAllQuoteState() async {
        let best = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "300000000"))
        let alt = SwapQuote.oneinch(makeEVMQuote(dstAmount: "100000000"), fee: nil)
        let vm = makeVM(best: best, allQuotes: [best, alt], providerSelectionUnlocked: true)
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"
        vm.updateFromAmount(vault: makeVault(), referredCode: "", immediate: true)
        await vm.waitForQuoteTask()
        vm.selectProvider(alt)

        vm.fromAmount = ""
        vm.updateFromAmount(vault: makeVault(), referredCode: "")

        XCTAssertNil(vm.quote, "Emptying the amount clears the active quote")
        XCTAssertNil(vm.selectedQuote, "Emptying the amount clears the manual override")
        XCTAssertTrue(vm.allQuotes.isEmpty, "Emptying the amount clears the ranked set")
    }

    // MARK: - Item 3: below-Silver invariant

    func testCanSelectProviderFalseWhenBelowSilver() async {
        let best = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "300000000"))
        let alt = SwapQuote.oneinch(makeEVMQuote(dstAmount: "100000000"), fee: nil)
        // Gate locked (below Silver): more than one quote, but the row
        // must stay static and a pick must not change the active quote.
        let vm = makeVM(best: best, allQuotes: [best, alt], providerSelectionUnlocked: false)
        await landQuotes(on: vm)

        XCTAssertFalse(
            vm.canSelectProvider,
            "Below Silver: provider selection must be unavailable even with multiple quotes"
        )

        vm.selectProvider(alt)
        XCTAssertNil(vm.selectedQuote, "A locked gate must ignore selection")
        XCTAssertEqual(vm.quote, best, "Below Silver: best stays auto-selected — exactly today's behavior")
    }

    func testCanSelectProviderFalseWithSingleQuote() async {
        let best = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "300000000"))
        // Unlocked, but only one quote → no chevron, no sheet.
        let vm = makeVM(best: best, allQuotes: [best], providerSelectionUnlocked: true)
        await landQuotes(on: vm)

        XCTAssertFalse(vm.canSelectProvider, "A single quote must not offer selection")
    }

    func testCanSelectProviderTrueWhenUnlockedWithMultipleQuotes() async {
        let best = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "300000000"))
        let alt = SwapQuote.oneinch(makeEVMQuote(dstAmount: "100000000"), fee: nil)
        let vm = makeVM(best: best, allQuotes: [best, alt], providerSelectionUnlocked: true)
        await landQuotes(on: vm)

        XCTAssertTrue(vm.canSelectProvider, "Unlocked + multiple quotes must offer selection")
    }

    // MARK: - Fixtures

    private func makeVM(
        best: SwapQuote,
        allQuotes: [SwapQuote],
        providerSelectionUnlocked: Bool
    ) -> SwapDetailsViewModel {
        let interactor = ProviderSelectionMockInteractor(
            best: best,
            allQuotes: allQuotes,
            providerSelectionUnlocked: providerSelectionUnlocked
        )
        let vm = SwapDetailsViewModel(interactor: interactor)
        vm.isProviderSelectionEnabled = providerSelectionUnlocked
        return vm
    }

    /// Drive a quote fetch to completion so `allQuotes`/`bestQuote` populate via
    /// the real VM path (not by poking state directly). Seeds a default RUNE→BTC
    /// pair + amount only when the caller hasn't set one, so tests exercising
    /// `makeTransaction` can pin specific coins first.
    private func landQuotes(on vm: SwapDetailsViewModel) async {
        if vm.fromCoin.chain == .bitcoin, vm.toCoin.chain == .bitcoin {
            vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
            vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        }
        if vm.fromAmount.isEmpty { vm.fromAmount = "1" }
        vm.updateFromAmount(vault: makeVault(), referredCode: "", immediate: true)
        await vm.waitForQuoteTask()
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

// MARK: - Test helpers

private extension SwapDetailsViewModel {
    func waitForQuoteTask() async {
        for _ in 0..<200 where isLoadingQuotes {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

// swiftlint:disable async_without_await unused_parameter

/// Returns a fixed best + ranked set so the VM's quote-landing path can be
/// driven without the network, and reports a configurable provider-selection
/// unlock so the gate invariant is testable.
@MainActor
private final class ProviderSelectionMockInteractor: SwapInteractor {
    private let best: SwapQuote
    private let allQuotes: [SwapQuote]
    private let providerSelectionUnlocked: Bool

    init(best: SwapQuote, allQuotes: [SwapQuote], providerSelectionUnlocked: Bool) {
        self.best = best
        self.allQuotes = allQuotes
        self.providerSelectionUnlocked = providerSelectionUnlocked
    }

    func fetchQuote(
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        vault: Vault,
        referredCode: String,
        thorPools: [NativePoolAsset]?,
        mayaPools: [NativePoolAsset]?
    ) async throws -> SwapQuoteResult? {
        SwapQuoteResult(quote: best, allQuotes: allQuotes, vultDiscountBps: 0, referralDiscountBps: 0)
    }

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

    func isProviderSelectionUnlocked(for vault: Vault) async -> Bool {
        providerSelectionUnlocked
    }
}

// swiftlint:enable async_without_await unused_parameter
