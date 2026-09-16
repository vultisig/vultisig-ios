//
//  SwapPayoutModelTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

@MainActor
final class SwapPayoutModelTests: XCTestCase {

    // A real ETH → BTC quote: a $12 trade whose cost is almost entirely the flat
    // BTC outbound fee.
    private let smallTradeAmount = Decimal(string: "0.005")!
    private var smallTradeQuote: SwapQuote {
        .thorchain(makeThorQuote(expectedAmountOut: "13805", feesTotal: "1820", feesOutbound: "1660"))
    }

    // MARK: - Native fit

    func testNativeFitSeparatesTheFlatFeeFromTheProportionalOne() throws {
        let btc = makeCoin(.bitcoin, ticker: "BTC")

        let model = try XCTUnwrap(SwapPayoutModel.fit(quote: smallTradeQuote, fromAmount: smallTradeAmount, toCoin: btc))

        XCTAssertEqual(model.rate, Decimal(string: "0.03125"))
        XCTAssertEqual(model.proportionalFeeFraction, Decimal(string: "0.01024"))
        XCTAssertEqual(model.flatFee, Decimal(string: "0.0000166"))
    }

    func testNativeFitReproducesTheQuoteAtTheFittedAmount() throws {
        let btc = makeCoin(.bitcoin, ticker: "BTC")
        let quote = smallTradeQuote

        let model = try XCTUnwrap(SwapPayoutModel.fit(quote: quote, fromAmount: smallTradeAmount, toCoin: btc))

        XCTAssertEqual(model.estimate(fromAmount: smallTradeAmount), SwapCryptoLogic.toAmountDecimal(quote: quote, toCoin: btc))
        XCTAssertEqual(model.estimate(fromAmount: smallTradeAmount), Decimal(string: "0.00013805"))
    }

    func testNativeFitAtHalfTheAmountKeepsTheFlatFeeWhole() throws {
        let btc = makeCoin(.bitcoin, ticker: "BTC")
        let model = try XCTUnwrap(SwapPayoutModel.fit(quote: smallTradeQuote, fromAmount: smallTradeAmount, toCoin: btc))

        let estimate = model.estimate(fromAmount: Decimal(string: "0.0025")!)

        XCTAssertEqual(estimate, Decimal(string: "0.000060725"))
        // Spot alone (0.0025 × 0.03125 = 0.000078125) overshoots this by more than a quarter.
        XCTAssertLessThan(estimate, Decimal(string: "0.0000625")!)
    }

    func testMayaFitDividesByTheDestinationCoinsOwnDecimals() throws {
        let cacao = makeCoin(.mayaChain, ticker: "CACAO", decimals: 10)
        let quote = SwapQuote.mayachain(makeThorQuote(expectedAmountOut: "9800000000", feesTotal: "200000000", feesOutbound: "100000000"))

        let model = try XCTUnwrap(SwapPayoutModel.fit(quote: quote, fromAmount: 1, toCoin: cacao))

        XCTAssertEqual(model.rate, 1)
        XCTAssertEqual(model.flatFee, Decimal(string: "0.01"))
        XCTAssertEqual(model.estimate(fromAmount: 1), Decimal(string: "0.98"))
    }

    func testSecuredMintQuoteFitsToUnitRate() throws {
        let btc = makeCoin(.bitcoin, ticker: "BTC")
        let quote = SwapCryptoLogic.securedMintQuote(fromAmount: Decimal(string: "1.5")!, toCoin: btc)

        let model = try XCTUnwrap(SwapPayoutModel.fit(quote: quote, fromAmount: Decimal(string: "1.5")!, toCoin: btc))

        XCTAssertEqual(model, SwapPayoutModel(rate: 1, proportionalFeeFraction: 0, flatFee: 0))
    }

    // MARK: - Aggregator fit

    func testAggregatorFitIsRateOnly() throws {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6)
        let quote = makeEVMQuote(dstAmount: "1000000")

        let model = try XCTUnwrap(SwapPayoutModel.fit(quote: .oneinch(quote, fee: nil), fromAmount: Decimal(string: "0.5")!, toCoin: usdc))

        XCTAssertEqual(model, SwapPayoutModel(rate: 2, proportionalFeeFraction: 0, flatFee: 0))
        XCTAssertEqual(model.estimate(fromAmount: 1), 2)
    }

    func testSwapKitFitParsesHumanUnitAmounts() throws {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18)

        let model = try XCTUnwrap(SwapPayoutModel.fit(quote: makeSwapKitQuote(expectedBuyAmount: "0.1"), fromAmount: Decimal(string: "0.01")!, toCoin: eth))

        XCTAssertEqual(model.rate, 10)
        XCTAssertEqual(model.estimate(fromAmount: Decimal(string: "0.02")!), Decimal(string: "0.2"))
    }

    // MARK: - Declines to fit

    func testImplausibleProportionalFeeDeclinesToFit() {
        let btc = makeCoin(.bitcoin, ticker: "BTC")
        let twoThirds = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "5000", feesTotal: "10000", feesOutbound: "0"))
        let exactlyHalf = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "10000", feesTotal: "10000", feesOutbound: "0"))

        XCTAssertNil(SwapPayoutModel.fit(quote: twoThirds, fromAmount: smallTradeAmount, toCoin: btc))
        XCTAssertNil(SwapPayoutModel.fit(quote: exactlyHalf, fromAmount: smallTradeAmount, toCoin: btc))
    }

    func testUnparsableFeeDeclinesToFit() {
        let btc = makeCoin(.bitcoin, ticker: "BTC")
        let badTotal = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "13805", feesTotal: "n/a", feesOutbound: "1660"))
        let badOutbound = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "13805", feesTotal: "1820", feesOutbound: "n/a"))

        XCTAssertNil(SwapPayoutModel.fit(quote: badTotal, fromAmount: smallTradeAmount, toCoin: btc))
        XCTAssertNil(SwapPayoutModel.fit(quote: badOutbound, fromAmount: smallTradeAmount, toCoin: btc))
    }

    func testInconsistentFeeBreakdownDeclinesToFit() {
        let btc = makeCoin(.bitcoin, ticker: "BTC")
        let outboundAboveTotal = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "13805", feesTotal: "1660", feesOutbound: "1820"))
        let negativeTotal = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "13805", feesTotal: "-1820", feesOutbound: "0"))

        XCTAssertNil(SwapPayoutModel.fit(quote: outboundAboveTotal, fromAmount: smallTradeAmount, toCoin: btc))
        XCTAssertNil(SwapPayoutModel.fit(quote: negativeTotal, fromAmount: smallTradeAmount, toCoin: btc))
    }

    func testNonPositiveAmountDeclinesToFit() {
        let btc = makeCoin(.bitcoin, ticker: "BTC")

        XCTAssertNil(SwapPayoutModel.fit(quote: smallTradeQuote, fromAmount: 0, toCoin: btc))
        XCTAssertNil(SwapPayoutModel.fit(quote: smallTradeQuote, fromAmount: -1, toCoin: btc))
    }

    func testNonPositiveOutputDeclinesToFit() {
        let btc = makeCoin(.bitcoin, ticker: "BTC")
        let zeroGross = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "0", feesTotal: "0", feesOutbound: "0"))
        let zeroOutputWithFees = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "0", feesTotal: "1820", feesOutbound: "1660"))
        let unreadableOutputWithFees = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "n/a", feesTotal: "1820", feesOutbound: "1660"))
        let zeroAggregator = SwapQuote.oneinch(makeEVMQuote(dstAmount: "0"), fee: nil)

        XCTAssertNil(SwapPayoutModel.fit(quote: zeroGross, fromAmount: 1, toCoin: btc))
        XCTAssertNil(SwapPayoutModel.fit(quote: zeroOutputWithFees, fromAmount: 1, toCoin: btc))
        XCTAssertNil(SwapPayoutModel.fit(quote: unreadableOutputWithFees, fromAmount: 1, toCoin: btc))
        XCTAssertNil(SwapPayoutModel.fit(quote: zeroAggregator, fromAmount: 1, toCoin: btc))
    }

    // MARK: - Estimate floor

    func testEstimateFloorsAtZeroBelowTheFlatFee() throws {
        let btc = makeCoin(.bitcoin, ticker: "BTC")
        let model = try XCTUnwrap(SwapPayoutModel.fit(quote: smallTradeQuote, fromAmount: smallTradeAmount, toCoin: btc))

        XCTAssertEqual(model.estimate(fromAmount: Decimal(string: "0.0000001")!), 0)
    }

    // MARK: - Fixtures

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int = 8) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: true)
        return Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
    }

    private func makeThorQuote(expectedAmountOut: String, feesTotal: String, feesOutbound: String) -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: expectedAmountOut,
            expiry: 0,
            fees: Fees(
                affiliate: "0",
                asset: "BTC.BTC",
                outbound: feesOutbound,
                total: feesTotal,
                liquidity: nil,
                slippageBps: nil,
                totalBps: nil
            ),
            inboundAddress: nil,
            inboundConfirmationBlocks: nil,
            inboundConfirmationSeconds: nil,
            memo: "=:BTC.BTC:bc1qexample",
            notes: "",
            outboundDelayBlocks: 0,
            outboundDelaySeconds: 0,
            recommendedMinAmountIn: "0",
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
                to: "0xrouter",
                data: "0x",
                value: "0",
                gasPrice: "0",
                gas: 0
            )
        )
    }

    private func makeSwapKitQuote(expectedBuyAmount: String) -> SwapQuote {
        let json = """
        {
          "swapId": "swap-1",
          "routeId": "route-1",
          "providers": ["Chainflip"],
          "sellAsset": "BTC.BTC",
          "buyAsset": "ETH.ETH",
          "sellAmount": "0.01",
          "expectedBuyAmount": "\(expectedBuyAmount)",
          "expectedBuyAmountMaxSlippage": "\(expectedBuyAmount)",
          "sourceAddress": "bc1from",
          "destinationAddress": "0xto",
          "targetAddress": "0xtarget",
          "meta": { "txType": "EVM" },
          "tx": {
            "from": "0xfrom",
            "to": "0xto",
            "value": "0",
            "data": "0x",
            "gas": "0x30d40",
            "gasPrice": "0x4a817c800"
          },
          "fees": []
        }
        """
        // Test fixture: a decode failure here is a test bug, so force-try is acceptable.
        // swiftlint:disable:next force_try
        let response = try! JSONDecoder().decode(SwapKitSwapResponse.self, from: Data(json.utf8))
        return .swapkit(response, fee: nil, subProvider: "Chainflip")
    }
}
