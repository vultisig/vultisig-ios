//
//  SwapCryptoLogicTests.swift
//  VultisigAppTests
//
//  Per-helper coverage for the primitive-based SwapCryptoLogic helpers.
//  Each non-trivial branch gets a row.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SwapCryptoLogicTests: XCTestCase {

    // MARK: - Amount conversions

    func testFromAmountDecimalParsesString() {
        XCTAssertEqual(SwapCryptoLogic.fromAmountDecimal(fromAmount: "1.5"), Decimal(string: "1.5"))
    }

    func testFromAmountDecimalEmptyReturnsZero() {
        XCTAssertEqual(SwapCryptoLogic.fromAmountDecimal(fromAmount: ""), .zero)
    }

    func testAmountInCoinDecimalScalesByCoinDecimals() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        XCTAssertEqual(SwapCryptoLogic.amountInCoinDecimal(fromAmount: "1.5", fromCoin: btc), BigInt(150_000_000))
    }

    // MARK: - fee

    func testFeeForThorchainQuoteUsesThorchainFee() {
        let result = SwapCryptoLogic.fee(quote: .thorchain(makeThorQuote()), fromCoin: makeBTC(), thorchainFee: BigInt(7_777))
        XCTAssertEqual(result, BigInt(7_777))
    }

    func testFeeForMayachainQuoteUsesThorchainFee() {
        let result = SwapCryptoLogic.fee(quote: .mayachain(makeThorQuote()), fromCoin: makeBTC(), thorchainFee: BigInt(99))
        XCTAssertEqual(result, BigInt(99))
    }

    func testFeeForOneInchQuoteUsesQuoteFee() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let result = SwapCryptoLogic.fee(quote: .oneinch(makeEVMQuote(), fee: BigInt(42)), fromCoin: eth, thorchainFee: BigInt(123))
        XCTAssertEqual(result, BigInt(42))
    }

    func testFeeForKyberSwapQuoteUsesQuoteFee() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let result = SwapCryptoLogic.fee(quote: .kyberswap(makeEVMQuote(), fee: BigInt(11)), fromCoin: eth, thorchainFee: .zero)
        XCTAssertEqual(result, BigInt(11))
    }

    func testFeeForLifiQuoteUsesQuoteFee() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let result = SwapCryptoLogic.fee(quote: .lifi(makeEVMQuote(), fee: BigInt(5), integratorFee: nil), fromCoin: eth, thorchainFee: .zero)
        XCTAssertEqual(result, BigInt(5))
    }

    func testFeeForEVMQuoteWithNilFeeReturnsZero() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let result = SwapCryptoLogic.fee(quote: .oneinch(makeEVMQuote(), fee: nil), fromCoin: eth, thorchainFee: .zero)
        XCTAssertEqual(result, .zero)
    }

    func testFeeForNilQuoteReturnsZero() {
        XCTAssertEqual(SwapCryptoLogic.fee(quote: nil, fromCoin: makeBTC(), thorchainFee: .zero), .zero)
    }

    // SwapKit UTXO sources surface a misleading wire `inbound` fee; the Network
    // Fee row must instead show the transaction-plan fee (carried in
    // `thorchainFee`), matching the Send flow.
    func testFeeForSwapKitUTXOSourceUsesPlanFee() {
        let result = SwapCryptoLogic.fee(
            quote: makeSwapKitQuote(fee: BigInt(80)),
            fromCoin: makeBTC(),
            thorchainFee: BigInt(12_345)
        )
        XCTAssertEqual(result, BigInt(12_345))
    }

    func testFeeForSwapKitCardanoSourceUsesPlanFee() {
        let ada = makeCoin(.cardano, ticker: "ADA", decimals: 6, isNative: true)
        let result = SwapCryptoLogic.fee(
            quote: makeSwapKitQuote(fee: BigInt(7)),
            fromCoin: ada,
            thorchainFee: BigInt(170_000)
        )
        XCTAssertEqual(result, BigInt(170_000))
    }

    // EVM (and other non-plan) SwapKit sources keep the wire-reported inbound fee.
    func testFeeForSwapKitEVMSourceUsesQuoteFee() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let result = SwapCryptoLogic.fee(
            quote: makeSwapKitQuote(fee: BigInt(42)),
            fromCoin: eth,
            thorchainFee: BigInt(999)
        )
        XCTAssertEqual(result, BigInt(42))
    }

    // MARK: - inboundFeeDecimal

    func testInboundFeeDecimalNilQuoteReturnsNil() {
        let rune = makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true)
        XCTAssertNil(SwapCryptoLogic.inboundFeeDecimal(quote: nil, toCoin: rune))
    }

    func testInboundFeeDecimalThorchainDelegatesToQuote() {
        let rune = makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true)
        // fees.total = 1_000 → 1_000 / 10^8 = 0.00001
        let quote = SwapQuote.thorchain(makeThorQuote(feesTotal: "1000"))
        XCTAssertEqual(SwapCryptoLogic.inboundFeeDecimal(quote: quote, toCoin: rune), Decimal(string: "0.00001"))
    }

    // MARK: - toAmountDecimal

    func testToAmountDecimalNilQuoteReturnsZero() {
        let rune = makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true)
        XCTAssertEqual(SwapCryptoLogic.toAmountDecimal(quote: nil, toCoin: rune), .zero)
    }

    func testToAmountDecimalThorchainDividesByMultiplier() {
        let rune = makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true)
        let quote = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "100000000"))
        XCTAssertEqual(SwapCryptoLogic.toAmountDecimal(quote: quote, toCoin: rune), 1)
    }

    func testToAmountDecimalOneInchUsesDstAmount() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let quote = SwapQuote.oneinch(makeEVMQuote(dstAmount: "1000000000000000000"), fee: nil)
        XCTAssertEqual(SwapCryptoLogic.toAmountDecimal(quote: quote, toCoin: eth), 1)
    }

    // MARK: - router

    func testRouterNilWhenQuoteNil() {
        XCTAssertNil(SwapCryptoLogic.router(quote: nil))
    }

    func testRouterFromThorchainQuote() {
        let quote = SwapQuote.thorchain(makeThorQuote(router: "0xRouter"))
        XCTAssertEqual(SwapCryptoLogic.router(quote: quote), "0xRouter")
    }

    func testRouterFromEVMQuoteUsesTxTo() {
        let quote = SwapQuote.oneinch(makeEVMQuote(toAddress: "0xAggregator"), fee: nil)
        XCTAssertEqual(SwapCryptoLogic.router(quote: quote), "0xAggregator")
    }

    // MARK: - isApproveRequired

    func testIsApproveRequiredFalseForNativeCoin() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let quote = SwapQuote.oneinch(makeEVMQuote(toAddress: "0xRouter"), fee: nil)
        XCTAssertFalse(SwapCryptoLogic.isApproveRequired(fromCoin: eth, quote: quote))
    }

    func testIsApproveRequiredFalseForNonEVMToken() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: false)
        let quote = SwapQuote.thorchain(makeThorQuote(router: "0xRouter"))
        XCTAssertFalse(SwapCryptoLogic.isApproveRequired(fromCoin: btc, quote: quote))
    }

    func testIsApproveRequiredTrueForERC20WithRouter() {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        let quote = SwapQuote.oneinch(makeEVMQuote(toAddress: "0xRouter"), fee: nil)
        XCTAssertTrue(SwapCryptoLogic.isApproveRequired(fromCoin: usdc, quote: quote))
    }

    func testIsApproveRequiredFalseForERC20WithoutQuote() {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        XCTAssertFalse(SwapCryptoLogic.isApproveRequired(fromCoin: usdc, quote: nil))
    }

    // MARK: - isDeposit

    func testIsDepositTrueForMayaChain() {
        let cacao = makeCoin(.mayaChain, ticker: "CACAO", decimals: 10, isNative: true)
        XCTAssertTrue(SwapCryptoLogic.isDeposit(fromCoin: cacao))
    }

    func testIsDepositFalseForThorChain() {
        let rune = makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true)
        XCTAssertFalse(SwapCryptoLogic.isDeposit(fromCoin: rune))
    }

    // MARK: - isAffiliate

    func testIsAffiliateAlwaysTrue() {
        XCTAssertTrue(SwapCryptoLogic.isAffiliate)
    }

    // MARK: - swapFeeCoin

    func testSwapFeeCoinMatchesFromCoinContractCaseInsensitively() {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let quote = SwapQuote.lifi(
            makeEVMQuote(swapFee: "1", swapFeeTokenContract: "usdc-CONTRACT"),
            fee: nil,
            integratorFee: nil
        )
        let result = SwapCryptoLogic.swapFeeCoin(quote: quote, fromCoin: usdc, toCoin: eth, feeCoin: eth)
        XCTAssertEqual(result.ticker, "USDC")
    }

    func testSwapFeeCoinMatchesToCoinContract() {
        // KyberSwap shape: fee denominated in the destination token.
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let quote = SwapQuote.kyberswap(
            makeEVMQuote(swapFee: "1", swapFeeTokenContract: "USDC-contract"),
            fee: nil
        )
        let result = SwapCryptoLogic.swapFeeCoin(quote: quote, fromCoin: eth, toCoin: usdc, feeCoin: eth)
        XCTAssertEqual(result.ticker, "USDC")
    }

    func testSwapFeeCoinFallsBackToFeeCoinWithoutContract() {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let quote = SwapQuote.oneinch(makeEVMQuote(swapFee: "1"), fee: nil)
        let result = SwapCryptoLogic.swapFeeCoin(quote: quote, fromCoin: usdc, toCoin: usdc, feeCoin: eth)
        XCTAssertEqual(result.ticker, "ETH")
    }

    func testSwapFeeCoinFallsBackToFeeCoinForUnknownContract() {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let quote = SwapQuote.kyberswap(
            makeEVMQuote(swapFee: "1", swapFeeTokenContract: "0xdeadbeef"),
            fee: nil
        )
        let result = SwapCryptoLogic.swapFeeCoin(quote: quote, fromCoin: usdc, toCoin: usdc, feeCoin: eth)
        XCTAssertEqual(result.ticker, "ETH")
    }

    // MARK: - Fixtures

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        return Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
    }

    private func makeBTC() -> Coin {
        makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
    }

    /// SwapKit quote fixture. The `fee` function only branches on the quote case
    /// and the source chain, so the response body shape (EVM here) is irrelevant.
    private func makeSwapKitQuote(fee: BigInt?) -> SwapQuote {
        let json = """
        {
          "swapId": "swap-1",
          "routeId": "route-1",
          "providers": ["Chainflip"],
          "sellAsset": "BTC.BTC",
          "buyAsset": "ETH.ETH",
          "sellAmount": "0.01",
          "expectedBuyAmount": "0.1",
          "expectedBuyAmountMaxSlippage": "0.1",
          "sourceAddress": "bc1from",
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
        // Test fixture: a decode failure here is a test bug, so force-try is acceptable.
        // swiftlint:disable:next force_try
        let response = try! JSONDecoder().decode(SwapKitSwapResponse.self, from: Data(json.utf8))
        return .swapkit(response, fee: fee, subProvider: "Chainflip")
    }

    private func makeThorQuote(
        expectedAmountOut: String = "0",
        feesTotal: String = "0",
        router: String? = nil
    ) -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: expectedAmountOut,
            expiry: 0,
            fees: Fees(
                affiliate: "0",
                asset: "RUNE",
                outbound: "0",
                total: feesTotal,
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
            router: router,
            maxStreamingQuantity: nil
        )
    }

    private func makeEVMQuote(
        dstAmount: String = "0",
        toAddress: String = "0xTo",
        swapFee: String = "0",
        swapFeeTokenContract: String = ""
    ) -> EVMQuote {
        EVMQuote(
            dstAmount: dstAmount,
            tx: EVMQuote.Transaction(
                from: "0xFrom",
                to: toAddress,
                data: "0x",
                value: "0",
                gasPrice: "0",
                gas: 0,
                swapFee: swapFee,
                swapFeeTokenContract: swapFeeTokenContract
            )
        )
    }
}
