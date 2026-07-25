import XCTest
@testable import VultisigApp

final class ThorchainAntiRektTests: XCTestCase {

    // MARK: - rapidSlippageBps

    func test_rapidSlippageBps_prefersAuthoritativeTotalBpsField() {
        // When fees.total_bps is returned by the node, we use it verbatim.
        let quote = makeQuote(expectedAmountOut: "100", feesTotal: "0", totalBps: 6434)

        XCTAssertEqual(SwapService.rapidSlippageBps(fromQuote: quote), 6434)
    }

    func test_rapidSlippageBps_catastrophicSlippage_exceedsThreshold() {
        // BTC → TRX case from issue #4205: expected $24,079 of TRX, $43,440 in fees
        let quote = makeQuote(expectedAmountOut: "24079", feesTotal: "43440", totalBps: nil)

        let bps = SwapService.rapidSlippageBps(fromQuote: quote)

        // 43440 / (24079 + 43440) = 64.34% = 6433 bps (truncated)
        XCTAssertEqual(bps, 6433)
        XCTAssertGreaterThan(bps ?? 0, SwapService.streamingSlippageThresholdBps)
    }

    func test_rapidSlippageBps_moderateSlippage_exceedsThreshold() {
        // BTC → XRP case from issue #4205: expected $55,720 of XRP, $12,504 in fees
        let quote = makeQuote(expectedAmountOut: "55720", feesTotal: "12504", totalBps: nil)

        let bps = SwapService.rapidSlippageBps(fromQuote: quote)

        // 12504 / (55720 + 12504) = 18.33% = 1832 bps (truncated)
        XCTAssertEqual(bps, 1832)
        XCTAssertGreaterThan(bps ?? 0, SwapService.streamingSlippageThresholdBps)
    }

    func test_rapidSlippageBps_belowThreshold_returnsSmallValue() {
        // Typical healthy trade: 0.5% slippage
        let quote = makeQuote(expectedAmountOut: "99500", feesTotal: "500", totalBps: nil)

        let bps = SwapService.rapidSlippageBps(fromQuote: quote)

        XCTAssertEqual(bps, 50)
        XCTAssertLessThan(bps ?? Int.max, SwapService.streamingSlippageThresholdBps)
    }

    // MARK: - 1% threshold boundary

    func test_rapidSlippageBps_justBelowOnePercent_doesNotTriggerStreaming() async {
        // 99 bps slippage — just under the 1% (100 bps) cutoff.
        // 99 / 10000 = 0.99% via authoritative totalBps field.
        let rapid = makeQuote(expectedAmountOut: "10000", feesTotal: "0", totalBps: 99)
        XCTAssertEqual(SwapService.rapidSlippageBps(fromQuote: rapid), 99)
        XCTAssertLessThan(SwapService.rapidSlippageBps(fromQuote: rapid) ?? .max, SwapService.streamingSlippageThresholdBps)

        let mock = MockSwapProvider(response: .success(makeQuote(expectedAmountOut: "999999", feesTotal: "0")))
        let result = await SwapService.shared.maybeUpgradeToStreaming(
            rapid: rapid, service: mock, provider: .thorchain,
            address: "addr", fromAsset: "BTC.BTC", toAsset: "TRX.TRX",
            amount: "100000000", referredCode: "", vultTierDiscount: 0
        )

        XCTAssertEqual(result.expectedAmountOut, rapid.expectedAmountOut)
        XCTAssertEqual(mock.callCount, 0, "Streaming must not be fetched at 99 bps with a 1% threshold")
    }

    func test_rapidSlippageBps_justAboveOnePercent_triggersStreamingFetch() async {
        // 101 bps slippage — just over the 1% (100 bps) cutoff.
        let rapid = makeQuote(expectedAmountOut: "10000", feesTotal: "0", totalBps: 101, maxStreamingQuantity: 10)
        XCTAssertEqual(SwapService.rapidSlippageBps(fromQuote: rapid), 101)
        XCTAssertGreaterThan(SwapService.rapidSlippageBps(fromQuote: rapid) ?? 0, SwapService.streamingSlippageThresholdBps)

        let streaming = makeQuote(expectedAmountOut: "20000", feesTotal: "0")
        let mock = MockSwapProvider(response: .success(streaming))
        let result = await SwapService.shared.maybeUpgradeToStreaming(
            rapid: rapid, service: mock, provider: .thorchain,
            address: "addr", fromAsset: "BTC.BTC", toAsset: "TRX.TRX",
            amount: "100000000", referredCode: "", vultTierDiscount: 0
        )

        XCTAssertEqual(result.expectedAmountOut, streaming.expectedAmountOut)
        XCTAssertEqual(mock.callCount, 1, "Streaming must be fetched at 101 bps with a 1% threshold")
        XCTAssertEqual(
            mock.lastLiquidityToleranceBps, SwapService.defaultLiquidityToleranceBps,
            "Streaming re-quote must carry the same liquidity_tolerance_bps as rapid, so the upgraded quote's memo LIM matches what the user was shown"
        )
        XCTAssertEqual(
            SwapService.defaultLiquidityToleranceBps, 100,
            "Auto slippage sends liquidity_tolerance_bps=100, so the node bakes a floor(expected × 0.99) LIM into the memo instead of leaving the swap unprotected"
        )
    }

    func test_rapidSlippageBps_zeroFees_returnsZero() {
        let quote = makeQuote(expectedAmountOut: "100000", feesTotal: "0", totalBps: nil)

        XCTAssertEqual(SwapService.rapidSlippageBps(fromQuote: quote), 0)
    }

    func test_rapidSlippageBps_unparseableValues_returnsNil() {
        let quote = makeQuote(expectedAmountOut: "not-a-number", feesTotal: "100", totalBps: nil)

        XCTAssertNil(SwapService.rapidSlippageBps(fromQuote: quote))
    }

    // MARK: - selectBetterQuote

    func test_selectBetterQuote_streamingHigher_picksStreaming() {
        let rapid = makeQuote(expectedAmountOut: "24079", feesTotal: "43440")
        let streaming = makeQuote(expectedAmountOut: "60000", feesTotal: "8000")

        let chosen = SwapService.selectBetterQuote(rapid: rapid, streaming: streaming)

        XCTAssertEqual(chosen.expectedAmountOut, streaming.expectedAmountOut)
    }

    func test_selectBetterQuote_streamingEqualOrLower_picksRapid() {
        let rapid = makeQuote(expectedAmountOut: "60000", feesTotal: "500")
        let streamingEqual = makeQuote(expectedAmountOut: "60000", feesTotal: "500")
        let streamingWorse = makeQuote(expectedAmountOut: "55000", feesTotal: "1000")

        XCTAssertEqual(
            SwapService.selectBetterQuote(rapid: rapid, streaming: streamingEqual).expectedAmountOut,
            rapid.expectedAmountOut
        )
        XCTAssertEqual(
            SwapService.selectBetterQuote(rapid: rapid, streaming: streamingWorse).expectedAmountOut,
            rapid.expectedAmountOut
        )
    }

    // MARK: - maybeUpgradeToStreaming — acceptance branches

    func test_maybeUpgradeToStreaming_belowThreshold_returnsRapidAndDoesNotFetchStreaming() async {
        let rapid = makeQuote(expectedAmountOut: "99500", feesTotal: "500")
        let mock = MockSwapProvider(response: .success(makeQuote(expectedAmountOut: "1", feesTotal: "0")))

        let result = await SwapService.shared.maybeUpgradeToStreaming(
            rapid: rapid, service: mock, provider: .thorchain,
            address: "addr", fromAsset: "BTC.BTC", toAsset: "TRX.TRX",
            amount: "100000000", referredCode: "", vultTierDiscount: 0
        )

        XCTAssertEqual(result.expectedAmountOut, rapid.expectedAmountOut)
        XCTAssertEqual(mock.callCount, 0, "Streaming quote must not be fetched when rapid slippage is below threshold")
    }

    func test_maybeUpgradeToStreaming_aboveThreshold_streamingBetter_returnsStreaming() async {
        let rapid = makeQuote(expectedAmountOut: "24079", feesTotal: "43440", maxStreamingQuantity: 10)
        let streaming = makeQuote(expectedAmountOut: "68000", feesTotal: "4000")
        let mock = MockSwapProvider(response: .success(streaming))

        let result = await SwapService.shared.maybeUpgradeToStreaming(
            rapid: rapid, service: mock, provider: .thorchain,
            address: "addr", fromAsset: "BTC.BTC", toAsset: "TRX.TRX",
            amount: "100000000", referredCode: "", vultTierDiscount: 0
        )

        XCTAssertEqual(result.expectedAmountOut, streaming.expectedAmountOut)
        XCTAssertEqual(mock.callCount, 1)
        XCTAssertEqual(mock.lastInterval, 1)
        XCTAssertEqual(mock.lastStreamingQuantity, 10)
    }

    func test_maybeUpgradeToStreaming_missingMaxStreamingQuantity_stillFetchesStreaming() async {
        // Rapid quotes (interval=0) typically omit max_streaming_quantity.
        // We must still fetch streaming — passing 0 tells THORChain to auto-pick.
        let rapid = makeQuote(expectedAmountOut: "24079", feesTotal: "43440", maxStreamingQuantity: nil)
        let streaming = makeQuote(expectedAmountOut: "68000", feesTotal: "4000")
        let mock = MockSwapProvider(response: .success(streaming))

        let result = await SwapService.shared.maybeUpgradeToStreaming(
            rapid: rapid, service: mock, provider: .thorchain,
            address: "addr", fromAsset: "BTC.BTC", toAsset: "TRX.TRX",
            amount: "100000000", referredCode: "", vultTierDiscount: 0
        )

        XCTAssertEqual(result.expectedAmountOut, streaming.expectedAmountOut)
        XCTAssertEqual(mock.callCount, 1)
        XCTAssertEqual(mock.lastInterval, 1)
        XCTAssertEqual(mock.lastStreamingQuantity, 0)
    }

    func test_maybeUpgradeToStreaming_aboveThreshold_streamingWorse_returnsRapid() async {
        let rapid = makeQuote(expectedAmountOut: "24079", feesTotal: "43440", maxStreamingQuantity: 10)
        let streaming = makeQuote(expectedAmountOut: "20000", feesTotal: "10000")
        let mock = MockSwapProvider(response: .success(streaming))

        let result = await SwapService.shared.maybeUpgradeToStreaming(
            rapid: rapid, service: mock, provider: .thorchain,
            address: "addr", fromAsset: "BTC.BTC", toAsset: "TRX.TRX",
            amount: "100000000", referredCode: "", vultTierDiscount: 0
        )

        XCTAssertEqual(result.expectedAmountOut, rapid.expectedAmountOut)
        XCTAssertEqual(mock.callCount, 1)
    }

    func test_maybeUpgradeToStreaming_streamingFetchFails_returnsRapidSilently() async {
        let rapid = makeQuote(expectedAmountOut: "24079", feesTotal: "43440", maxStreamingQuantity: 10)
        let mock = MockSwapProvider(response: .failure(NSError(domain: "test", code: -1)))

        let result = await SwapService.shared.maybeUpgradeToStreaming(
            rapid: rapid, service: mock, provider: .thorchain,
            address: "addr", fromAsset: "BTC.BTC", toAsset: "TRX.TRX",
            amount: "100000000", referredCode: "", vultTierDiscount: 0
        )

        XCTAssertEqual(result.expectedAmountOut, rapid.expectedAmountOut)
        XCTAssertEqual(mock.callCount, 1)
    }

    func test_maybeUpgradeToStreaming_mayachain_skipsFallback() async {
        let rapid = makeQuote(expectedAmountOut: "24079", feesTotal: "43440", maxStreamingQuantity: 10)
        let mock = MockSwapProvider(response: .success(makeQuote(expectedAmountOut: "999999", feesTotal: "0")))

        let result = await SwapService.shared.maybeUpgradeToStreaming(
            rapid: rapid, service: mock, provider: .mayachain,
            address: "addr", fromAsset: "BTC.BTC", toAsset: "TRX.TRX",
            amount: "100000000", referredCode: "", vultTierDiscount: 0
        )

        XCTAssertEqual(result.expectedAmountOut, rapid.expectedAmountOut)
        XCTAssertEqual(mock.callCount, 0, "Maya is out of scope and must not trigger a second fetch")
    }

    // MARK: - makeSwapQuote network tagging

    func testMakeSwapQuoteTagsEachServiceWithItsNetworkCase() {
        // Pins the concrete-service → SwapQuote-case mapping. The network
        // (mainnet / chainnet / stagenet) is carried only by the service type,
        // so a future edit that drops or misroutes a case regresses here.
        let quote = makeQuote(expectedAmountOut: "100", feesTotal: "0")

        guard case .thorchain(let thorMapped) = ThorchainService.shared.makeSwapQuote(quote) else {
            return XCTFail("ThorchainService must map to .thorchain")
        }
        XCTAssertEqual(thorMapped, quote)

        guard case .thorchainChainnet(let chainnetMapped) = ThorchainChainnetService.shared.makeSwapQuote(quote) else {
            return XCTFail("ThorchainChainnetService must map to .thorchainChainnet")
        }
        XCTAssertEqual(chainnetMapped, quote)

        guard case .thorchainStagenet(let stagenetMapped) = ThorchainStagenetService.shared.makeSwapQuote(quote) else {
            return XCTFail("ThorchainStagenetService must map to .thorchainStagenet")
        }
        XCTAssertEqual(stagenetMapped, quote)

        guard case .mayachain(let mayaMapped) = MayachainService.shared.makeSwapQuote(quote) else {
            return XCTFail("MayachainService must map to .mayachain")
        }
        XCTAssertEqual(mayaMapped, quote)
    }

    // MARK: - Helpers

    private func makeQuote(
        expectedAmountOut: String,
        feesTotal: String,
        totalBps: Int? = nil,
        maxStreamingQuantity: Int? = 10,
        memo: String = "=:TRX.TRX:addr"
    ) -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: expectedAmountOut,
            expiry: 0,
            fees: Fees(
                affiliate: "0",
                asset: "TRX.TRX",
                outbound: "0",
                total: feesTotal,
                liquidity: nil,
                slippageBps: nil,
                totalBps: totalBps
            ),
            inboundAddress: nil,
            inboundConfirmationBlocks: nil,
            inboundConfirmationSeconds: nil,
            memo: memo,
            notes: "",
            outboundDelayBlocks: 0,
            outboundDelaySeconds: 0,
            recommendedMinAmountIn: "0",
            slippageBps: nil,
            totalSwapSeconds: nil,
            warning: "",
            router: nil,
            maxStreamingQuantity: maxStreamingQuantity
        )
    }
}

private final class MockSwapProvider: ThorchainSwapProvider {
    var response: Result<ThorchainSwapQuote, Error>
    private(set) var callCount = 0
    private(set) var lastInterval: Int?
    private(set) var lastStreamingQuantity: Int?
    private(set) var lastLiquidityToleranceBps: Int?

    init(response: Result<ThorchainSwapQuote, Error>) {
        self.response = response
    }

    func fetchSwapQuotes(
        address _: String,
        fromAsset _: String,
        toAsset _: String,
        amount _: String,
        interval: Int,
        streamingQuantity: Int,
        liquidityToleranceBps: Int,
        referredCode _: String,
        vultTierDiscount _: Int
    ) async throws -> ThorchainSwapQuote {
        await Task.yield()
        callCount += 1
        lastInterval = interval
        lastStreamingQuantity = streamingQuantity
        lastLiquidityToleranceBps = liquidityToleranceBps
        return try response.get()
    }

    func makeSwapQuote(_ quote: ThorchainSwapQuote) -> SwapQuote {
        .thorchain(quote)
    }
}
