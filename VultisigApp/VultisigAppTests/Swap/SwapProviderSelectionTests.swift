//
//  SwapProviderSelectionTests.swift
//  VultisigAppTests
//
//  Covers the provider-selection feature:
//   1. Ranking — `SwapService.rankedQuotes` sorts best→worst by
//      `expectedNetToAmount`, and `selectBestQuote`'s winner is the rate-top
//      when no provider-preference band applies.
//   2. VM selection — `selectedQuote` drives the computed `quote` and a non-best
//      pick reaches the active quote (and therefore the verify/sign summary).
//   3. Pick persistence — a refresh re-resolves the pick by `routeIdentity`, so
//      it survives while its route is still a candidate and re-points at the
//      fresh quote; it is dropped, with a notice, when the route leaves the
//      candidate set or the swap itself changes.
//   4. Availability — provider selection depends solely on `allQuotes.count > 1`
//      (the advanced-settings entry point is already silver-gated, so there is
//      no second tier gate on the row itself).
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
        let vm = makeVM(best: best, allQuotes: [best, alt])
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
        let vm = makeVM(best: best, allQuotes: [best, alt])
        vm.fromCoin = makeCoin(.ethereum, ticker: "ETH", balance: "5000000000000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"
        await landQuotes(on: vm)

        vm.selectProvider(alt)
        let transaction = vm.makeTransaction()

        XCTAssertNotNil(transaction, "Form should validate with a firm quote")
        XCTAssertEqual(transaction?.quote, alt, "The non-best pick must carry into the signed transaction")
    }

    func testEmptyAmountClearsAllQuoteState() async {
        let best = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "300000000"))
        let alt = SwapQuote.oneinch(makeEVMQuote(dstAmount: "100000000"), fee: nil)
        let vm = makeVM(best: best, allQuotes: [best, alt])
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"
        vm.updateFromAmount(vault: makeVault(), immediate: true)
        await vm.waitForQuoteTask()
        vm.selectProvider(alt)

        vm.fromAmount = ""
        vm.updateFromAmount(vault: makeVault())

        XCTAssertNil(vm.quote, "Emptying the amount clears the active quote")
        XCTAssertNil(vm.selectedQuote, "Emptying the amount clears the manual override")
        XCTAssertTrue(vm.allQuotes.isEmpty, "Emptying the amount clears the ranked set")
    }

    // MARK: - Item 3: the pick survives a refresh

    func testRefreshPreservesManualRouteSelection() async {
        let best = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "300000000"))
        let alt = SwapQuote.oneinch(makeEVMQuote(dstAmount: "100000000"), fee: nil)
        let vm = makeVM(best: best, allQuotes: [best, alt])
        await landQuotes(on: vm)

        vm.selectProvider(alt)
        XCTAssertEqual(vm.quote, alt)

        // A silent same-pair/same-amount refresh — the 60s auto-refresh.
        await landQuotes(on: vm)

        XCTAssertEqual(vm.selectedQuote, alt, "A refresh must not drop a still-valid manual pick")
        XCTAssertEqual(vm.quote, alt, "The active quote stays on the picked route")
        XCTAssertNil(vm.routeSelectionNotice, "Nothing was dropped, so there is nothing to tell the user")
    }

    func testRefreshRepointsSelectionAtFreshQuoteForSameRoute() async {
        let best = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "300000000"))
        // Same route, different payload — what a real refresh returns.
        let stale = SwapQuote.oneinch(makeEVMQuote(dstAmount: "100000000"), fee: BigInt(1_000))
        let fresh = SwapQuote.oneinch(makeEVMQuote(dstAmount: "123456789"), fee: BigInt(1_000))
        XCTAssertNotEqual(stale, fresh, "Fixture must differ by payload for this test to mean anything")
        XCTAssertEqual(stale.routeIdentity, fresh.routeIdentity, "…while still being the same route")

        let vm = makeVM(script: [
            makeResult(best: best, allQuotes: [best, stale]),
            makeResult(best: best, allQuotes: [best, fresh])
        ])
        vm.fromCoin = makeCoin(.ethereum, ticker: "ETH", balance: "5000000000000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"
        await landQuotes(on: vm)

        vm.selectProvider(stale)
        await landQuotes(on: vm)

        XCTAssertEqual(vm.selectedQuote, fresh, "The pick must re-point at the refreshed quote")
        XCTAssertEqual(
            vm.makeTransaction()?.quote,
            fresh,
            "Signing must carry the refreshed quote, never the one the user tapped"
        )
    }

    func testRefreshDropsSelectionWhenRouteLeavesCandidateSet() async {
        let best = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "300000000"))
        let alt = SwapQuote.oneinch(makeEVMQuote(dstAmount: "100000000"), fee: nil)
        let vm = makeVM(script: [
            makeResult(best: best, allQuotes: [best, alt]),
            makeResult(best: best, allQuotes: [best])
        ])
        await landQuotes(on: vm)

        vm.selectProvider(alt)
        await landQuotes(on: vm)

        XCTAssertNil(vm.selectedQuote, "A route that is no longer offered can't stay picked")
        XCTAssertEqual(vm.quote, best, "The active quote falls back to the auto-selected winner")
        XCTAssertEqual(
            vm.routeSelectionNotice,
            "swapRouteUnavailableResetToAuto".localized,
            "Dropping the pick must be surfaced, not silent"
        )
    }

    func testAmountChangeDropsSelectionWithNotice() async {
        let best = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "300000000"))
        let alt = SwapQuote.oneinch(makeEVMQuote(dstAmount: "100000000"), fee: nil)
        let vm = makeVM(best: best, allQuotes: [best, alt])
        await landQuotes(on: vm)
        vm.selectProvider(alt)

        vm.fromAmount = "2"
        vm.updateFromAmount(vault: makeVault(), immediate: true)

        XCTAssertNil(vm.selectedQuote, "A new amount invalidates the pick")
        XCTAssertEqual(vm.routeSelectionNotice, "swapRouteResetToAuto".localized)

        await vm.waitForQuoteTask()
        XCTAssertNil(vm.selectedQuote, "The refetch must not resurrect the dropped pick")
        XCTAssertEqual(vm.quote, best)
    }

    func testPairChangeDropsSelectionWithNotice() async {
        let best = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "300000000"))
        let alt = SwapQuote.oneinch(makeEVMQuote(dstAmount: "100000000"), fee: nil)
        let vm = makeVM(best: best, allQuotes: [best, alt])
        await landQuotes(on: vm)
        vm.selectProvider(alt)

        vm.updateToCoin(coin: makeCoin(.ethereum, ticker: "ETH"), vault: makeVault())

        XCTAssertNil(vm.selectedQuote, "A new pair invalidates the pick")
        XCTAssertEqual(vm.routeSelectionNotice, "swapRouteResetToAuto".localized)
    }

    func testDropNoticeKeysAreBundled() {
        // `.localized` echoes a missing key back, so assert both keys resolve.
        XCTAssertNotEqual("swapRouteResetToAuto".localized, "swapRouteResetToAuto")
        XCTAssertNotEqual("swapRouteUnavailableResetToAuto".localized, "swapRouteUnavailableResetToAuto")
    }

    // MARK: - Route identity

    func testRouteIdentityIsStableAcrossPayloadChanges() {
        let stale = SwapQuote.lifi(makeEVMQuote(dstAmount: "100000000"), fee: BigInt(1), integratorFee: 0.001)
        let fresh = SwapQuote.lifi(makeEVMQuote(dstAmount: "999999999"), fee: BigInt(2), integratorFee: 0.002)

        XCTAssertNotEqual(stale, fresh, "Quotes compare by payload, so these are different values")
        XCTAssertEqual(stale.routeIdentity, fresh.routeIdentity, "…but the same route")
    }

    func testRouteIdentityIsDistinctPerPickerRow() {
        let quotes: [SwapQuote] = [
            .thorchain(makeThorQuote(expectedAmountOut: "1")),
            .thorchainChainnet(makeThorQuote(expectedAmountOut: "1")),
            .thorchainStagenet(makeThorQuote(expectedAmountOut: "1")),
            .mayachain(makeThorQuote(expectedAmountOut: "1")),
            .oneinch(makeEVMQuote(dstAmount: "1"), fee: nil),
            .kyberswap(makeEVMQuote(dstAmount: "1"), fee: nil),
            .lifi(makeEVMQuote(dstAmount: "1"), fee: nil, integratorFee: nil),
            .swapkit(makeSwapKitResponse(), fee: nil, subProvider: "Chainflip"),
            .jupiter(makeEVMQuote(dstAmount: "1"), fee: nil, platformFee: 0, feeOnInput: false)
        ]

        XCTAssertEqual(
            Set(quotes.map(\.routeIdentity)).count,
            quotes.count,
            "Every route the picker can show must be separately identifiable"
        )
        XCTAssertEqual(
            Set(quotes.compactMap(\.displayName)).count,
            quotes.count,
            "…and the identity must be as fine-grained as the row labels the user sees"
        )
    }

    func testRouteIdentityIgnoresSwapKitSubProvider() {
        // SwapKit is one row whichever protocol it routes through underneath, and
        // that underlying choice can legitimately change between fetches — keying
        // on it would drop a pick the user can still see on screen.
        let viaChainflip = SwapQuote.swapkit(
            makeSwapKitResponse(providers: ["Chainflip"]), fee: nil, subProvider: "Chainflip"
        )
        let viaNear = SwapQuote.swapkit(
            makeSwapKitResponse(providers: ["NEAR"]), fee: nil, subProvider: "NEAR"
        )

        XCTAssertEqual(viaChainflip.routeIdentity, viaNear.routeIdentity)
    }

    // MARK: - Item 4: availability depends only on the quote count

    func testCanSelectProviderFalseWithSingleQuote() async {
        let best = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "300000000"))
        // Only one quote → no chevron, no sheet.
        let vm = makeVM(best: best, allQuotes: [best])
        await landQuotes(on: vm)

        XCTAssertFalse(vm.canSelectProvider, "A single quote must not offer selection")
    }

    func testCanSelectProviderTrueWithMultipleQuotes() async {
        let best = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "300000000"))
        let alt = SwapQuote.oneinch(makeEVMQuote(dstAmount: "100000000"), fee: nil)
        let vm = makeVM(best: best, allQuotes: [best, alt])
        await landQuotes(on: vm)

        XCTAssertTrue(vm.canSelectProvider, "Multiple quotes must offer selection (no tier gate)")
    }

    // MARK: - Fixtures

    private func makeVM(
        best: SwapQuote,
        allQuotes: [SwapQuote]
    ) -> SwapDetailsViewModel {
        makeVM(script: [makeResult(best: best, allQuotes: allQuotes)])
    }

    /// A VM whose interactor hands out `script` one entry per fetch, so a test
    /// can make a refresh return something different from the first landing.
    private func makeVM(script: [SwapQuoteResult]) -> SwapDetailsViewModel {
        SwapDetailsViewModel(interactor: ProviderSelectionMockInteractor(script: script))
    }

    private func makeResult(best: SwapQuote, allQuotes: [SwapQuote]) -> SwapQuoteResult {
        SwapQuoteResult(quote: best, allQuotes: allQuotes, vultDiscountBps: 0, referralDiscountBps: 0)
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
        vm.updateFromAmount(vault: makeVault(), immediate: true)
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

    /// SwapKit responses are `Decodable`-only (custom `init(from:)`, no memberwise
    /// init), so the fixture is built from a minimal EVM-txType JSON payload.
    private func makeSwapKitResponse(providers: [String] = ["Chainflip"]) -> SwapKitSwapResponse {
        let providerList = providers.map { "\"\($0)\"" }.joined(separator: ", ")
        let json = """
        {
          "swapId": "swap-1",
          "routeId": "route-1",
          "providers": [\(providerList)],
          "sellAsset": "ETH.USDC",
          "buyAsset": "ETH.ETH",
          "sellAmount": "10",
          "expectedBuyAmount": "1",
          "expectedBuyAmountMaxSlippage": "1",
          "sourceAddress": "0xfrom",
          "destinationAddress": "0xto",
          "targetAddress": "0xtarget",
          "meta": { "txType": "EVM" },
          "tx": {
            "from": "0xfrom",
            "to": "0xto",
            "value": "0",
            "data": "0x",
            "gas": "200000",
            "gasPrice": "20000000000"
          },
          "fees": []
        }
        """
        // Test fixture: a decode failure here is a test bug, so force-unwrap is acceptable.
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(SwapKitSwapResponse.self, from: Data(json.utf8))
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

/// Hands out a scripted result per fetch so the VM's quote-landing path can be
/// driven without the network, including a refresh that returns a different
/// candidate set from the first landing. The last entry repeats once the script
/// is exhausted, so a steady-state test can pass a single one.
@MainActor
private final class ProviderSelectionMockInteractor: SwapInteractor {
    private let script: [SwapQuoteResult]
    private var fetchCount = 0

    init(script: [SwapQuoteResult]) {
        precondition(!script.isEmpty, "The script needs at least one result")
        self.script = script
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
        defer { fetchCount += 1 }
        return script[min(fetchCount, script.count - 1)]
    }

    func assertSourceChainNotHalted(transaction: SwapTransaction) async throws {}

    func fetchChainSpecific(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmount: Decimal,
        quote: SwapQuote?
    ) async throws -> BlockChainSpecific {
        .Cosmos(accountNumber: 0, sequence: 0, gas: 0, transactionType: 0, ibcDenomTrace: nil, gasLimit: nil)
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
