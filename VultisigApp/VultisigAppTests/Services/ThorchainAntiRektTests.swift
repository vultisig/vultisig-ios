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
        referredCode _: String,
        vultTierDiscount _: Int
    ) async throws -> ThorchainSwapQuote {
        await Task.yield()
        callCount += 1
        lastInterval = interval
        lastStreamingQuantity = streamingQuantity
        return try response.get()
    }
}
