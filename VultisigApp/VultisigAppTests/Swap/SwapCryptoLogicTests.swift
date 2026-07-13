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

    func testIsDepositTrueForNativeCacao() {
        let cacao = makeCoin(.mayaChain, ticker: "CACAO", decimals: 10, isNative: true)
        XCTAssertTrue(SwapCryptoLogic.isDeposit(fromCoin: cacao))
    }

    func testIsDepositTrueForNativeRune() {
        // Native RUNE → MsgDeposit on THORChain itself. Was returning
        // false before, which broke RUNE-source swaps (no inbound vault).
        let rune = makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true)
        XCTAssertTrue(SwapCryptoLogic.isDeposit(fromCoin: rune))
    }

    func testIsDepositTrueForNativeRuneOnStagenet() {
        let rune = makeCoin(.thorChainStagenet, ticker: "RUNE", decimals: 8, isNative: true)
        XCTAssertTrue(SwapCryptoLogic.isDeposit(fromCoin: rune))
    }

    func testIsDepositTrueForNonNativeMayaToken() {
        // MayaChain settles ALL its source swaps via MsgDeposit — native CACAO
        // and non-native Maya assets (e.g. MAYA) alike. Keying Maya on
        // `isNativeToken` (as the THORChain arm is) flips a non-native Maya
        // market swap to an empty router and it fails to sign. Market Maya
        // behaviour is unconditional deposit.
        let mayaToken = makeCoin(.mayaChain, ticker: "MAYA", decimals: 6, isNative: false)
        XCTAssertTrue(SwapCryptoLogic.isDeposit(fromCoin: mayaToken))
    }

    func testIsDepositFalseForBitcoin() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        XCTAssertFalse(SwapCryptoLogic.isDeposit(fromCoin: btc))
    }

    func testIsDepositFalseForEthereum() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        XCTAssertFalse(SwapCryptoLogic.isDeposit(fromCoin: eth))
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

    // MARK: - EVM displayed network fee (shared initiator/co-signer derivation)

    func testDisplayedNetworkFeeForEvmAggregatorUsesSignedGasNotQuoteGasPrice() {
        // Initiator display matches the co-signer and the signed transaction:
        // maxFeePerGas × routeGas, not the aggregator's own routeGas × gasPrice.
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let maxFeePerGas = BigInt(592_930_334)
        let routeGas: Int64 = 359_942
        // Aggregator's quote fee (routeGas × its own stale 0.5 Gwei gasPrice).
        let quoteFee = BigInt(routeGas) * BigInt(500_000_000)
        let quote: SwapQuote = .oneinch(makeEVMQuote(gas: routeGas, gasPrice: "500000000"), fee: quoteFee)

        let result = SwapCryptoLogic.displayedSwapNetworkFeeWei(
            quote: quote, feeCoin: eth, gas: maxFeePerGas, gasLimit: BigInt(40_000), fee: quoteFee
        )

        XCTAssertEqual(result, maxFeePerGas * BigInt(routeGas))
        XCTAssertNotEqual(result, quoteFee, "Displayed fee must use maxFeePerGas, not the aggregator's stale gasPrice")
    }

    func testDisplayedNetworkFeeUsesQuoteGasPriceWhenAboveOracle() {
        // A provider pricing ABOVE our oracle wins the signed max — the display
        // must not under-report against the signed bond.
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let maxFeePerGas = BigInt(1_000_000_000)
        let routeGas: Int64 = 359_942
        let quoteGasPrice = BigInt(3_000_000_000)
        let quote: SwapQuote = .oneinch(makeEVMQuote(gas: routeGas, gasPrice: "3000000000"), fee: nil)

        let result = SwapCryptoLogic.displayedSwapNetworkFeeWei(
            quote: quote, feeCoin: eth, gas: maxFeePerGas, gasLimit: BigInt(40_000), fee: .zero
        )

        XCTAssertEqual(result, quoteGasPrice * BigInt(routeGas))
    }

    func testDisplayedNetworkFeeUsesOracleGasLimitWhenAboveRouteGas() {
        // Token routes commonly store a 600k-default ×1.5 inflated limit that
        // beats the route gas — the signed bond (and so the display) uses it.
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let maxFeePerGas = BigInt(1_000_000_000)
        let quote: SwapQuote = .lifi(makeEVMQuote(gas: 359_942, gasPrice: "500000000"), fee: nil, integratorFee: nil)

        let result = SwapCryptoLogic.displayedSwapNetworkFeeWei(
            quote: quote, feeCoin: eth, gas: maxFeePerGas, gasLimit: BigInt(900_000), fee: .zero
        )

        XCTAssertEqual(result, maxFeePerGas * BigInt(900_000))
    }

    func testDisplayedFeeMatchesSignedBondForSwapKitEvm() {
        // SwapKit EVM quotes ship stale hex gas prices (observed 0.077 Gwei on
        // mainnet); the broadcast bumps to the oracle. The displayed fee must
        // be the oracle-bumped signed bond, not the stale gasPrice × gas seed.
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let routeGas = BigInt(210_000)     // 0x33450
        let staleGasPrice = BigInt(1_000_000_000) // 0x3b9aca00, 1 Gwei
        let staleSeed = staleGasPrice * routeGas
        let maxFeePerGas = BigInt(5_000_000_000) // oracle at 5 Gwei
        let quote = makeSwapKitQuote(fee: staleSeed, gasHex: "0x33450", gasPriceHex: "0x3b9aca00")

        let result = SwapCryptoLogic.displayedSwapNetworkFeeWei(
            quote: quote, feeCoin: eth, gas: maxFeePerGas, gasLimit: BigInt(40_000), fee: staleSeed
        )

        XCTAssertEqual(result, maxFeePerGas * routeGas)
        XCTAssertNotEqual(result, staleSeed, "Displayed fee must not be SwapKit's stale gasPrice × gas")
    }

    func testDisplayedFeeForSwapKitEvmZeroGasUsesSignedFallback() {
        // A SwapKit route omitting its gas is signed with the 600k default —
        // the display must reproduce the SIGNED normalization, not the
        // 600k/120k display seed fallback in SwapKitService.
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let maxFeePerGas = BigInt(1_000_000_000)
        let quote = makeSwapKitQuote(fee: nil, gasHex: "0x0", gasPriceHex: "0x3b9aca00")

        let result = SwapCryptoLogic.displayedSwapNetworkFeeWei(
            quote: quote, feeCoin: eth, gas: maxFeePerGas, gasLimit: BigInt(40_000), fee: .zero
        )

        XCTAssertEqual(result, maxFeePerGas * BigInt(EVMHelper.defaultETHSwapGasUnit))
    }

    func testEvmRouteGasAndQuoteGasPriceParseSwapKitHex() {
        let quote = makeSwapKitQuote(fee: nil, gasHex: "0x33450", gasPriceHex: "0x3b9aca00")
        XCTAssertEqual(quote.evmRouteGas, BigInt(210_000))
        XCTAssertEqual(quote.evmQuoteGasPriceWei, BigInt(1_000_000_000))
    }

    func testDisplayedNetworkFeeFallsBackToFeeForThorchainSwap() {
        let rune = makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true)
        let quote: SwapQuote = .thorchain(makeThorQuote())

        let result = SwapCryptoLogic.displayedSwapNetworkFeeWei(
            quote: quote, feeCoin: rune, gas: BigInt(1_000), gasLimit: .zero, fee: BigInt(7_777)
        )

        XCTAssertEqual(result, BigInt(7_777), "Native-protocol swaps have no route gas and keep the quote fee")
    }

    func testDisplayedNetworkFeeFallsBackToFeeBeforeGasLoads() {
        // `gas` (maxFeePerGas) is zero until the EIP-1559 fee lands; keep the
        // quote fee rather than valuing the fee at zero.
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let quoteFee = BigInt(180_000_000_000_000)
        let quote: SwapQuote = .oneinch(makeEVMQuote(gas: 359_942, gasPrice: "500000000"), fee: quoteFee)

        let result = SwapCryptoLogic.displayedSwapNetworkFeeWei(
            quote: quote, feeCoin: eth, gas: .zero, gasLimit: .zero, fee: quoteFee
        )

        XCTAssertEqual(result, quoteFee)
    }

    // MARK: - limit-order network fee string

    func testLimitNetworkFeeStringFormatsWholeUnitAmount() {
        let rune = makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true)
        // 2 * 1e8 base units = 2 RUNE; whole number → locale-separator-independent.
        XCTAssertEqual(SwapCryptoLogic.limitNetworkFeeString(feeCoin: rune, fee: BigInt(200_000_000)), "2 RUNE")
    }

    func testLimitNetworkFeeStringFormatsFractionalAmountWithTicker() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let str = SwapCryptoLogic.limitNetworkFeeString(feeCoin: eth, fee: BigInt(3_840_000))
        XCTAssertTrue(str.hasSuffix(" ETH"), "got \(str)")
        XCTAssertTrue(str.hasPrefix("0"), "sub-unit fee should render as 0.<…>; got \(str)")
    }

    func testLimitNetworkFeeStringEmptyForZeroFee() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        XCTAssertEqual(SwapCryptoLogic.limitNetworkFeeString(feeCoin: eth, fee: .zero), "")
    }

    func testLimitNetworkFeeFiatEmptyForZeroFee() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        XCTAssertEqual(SwapCryptoLogic.limitNetworkFeeFiat(feeCoin: eth, fee: .zero), "")
    }

    // MARK: - Fixtures

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        return Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
    }

    private func makeBTC() -> Coin {
        makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
    }

    /// SwapKit quote fixture with an EVM tx body. `gasHex`/`gasPriceHex` mirror
    /// the wire encoding (Ethers-style hex strings); defaults only matter to the
    /// tests that read them — the `fee` function branches purely on the quote
    /// case and the source chain.
    private func makeSwapKitQuote(
        fee: BigInt?,
        gasHex: String = "0x30d40",
        gasPriceHex: String = "0x4a817c800"
    ) -> SwapQuote {
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
            "gas": "\(gasHex)",
            "gasPrice": "\(gasPriceHex)"
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
        swapFeeTokenContract: String = "",
        gas: Int64 = 0,
        gasPrice: String = "0"
    ) -> EVMQuote {
        EVMQuote(
            dstAmount: dstAmount,
            tx: EVMQuote.Transaction(
                from: "0xFrom",
                to: toAddress,
                data: "0x",
                value: "0",
                gasPrice: gasPrice,
                gas: gas,
                swapFee: swapFee,
                swapFeeTokenContract: swapFeeTokenContract
            )
        )
    }
}
