//
//  SwapValidationTests.swift
//  VultisigAppTests
//
//  Coverage for the primitive-based swap-validation helpers — feeCoin,
//  balanceError, isSufficientBalance, validateForm.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SwapValidationTests: XCTestCase {

    // MARK: - feeCoin

    func testFeeCoinReturnsFromCoinWhenNative() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        XCTAssertEqual(SwapCryptoLogic.feeCoin(fromCoin: btc, fromCoins: []), btc)
    }

    func testFeeCoinReturnsNativeSiblingForERC20() {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        XCTAssertEqual(SwapCryptoLogic.feeCoin(fromCoin: usdc, fromCoins: [usdc, eth]), eth)
    }

    func testFeeCoinFallsBackToFromCoinWhenNoNativeSibling() {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        XCTAssertEqual(SwapCryptoLogic.feeCoin(fromCoin: usdc, fromCoins: [usdc]), usdc)
    }

    // MARK: - balanceError — same-coin pays for amount + gas

    func testBalanceErrorNilWhenAmountPlusFeeFits() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true, rawBalance: "100000000") // 1 BTC
        XCTAssertNil(SwapCryptoLogic.balanceError(fromCoin: btc, feeCoin: btc, fromAmount: "0.5", fee: BigInt(1_000)))
    }

    func testBalanceErrorInsufficientFundsWhenAmountAlreadyExceedsBalance() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true, rawBalance: "50000000") // 0.5 BTC
        XCTAssertEqual(
            SwapCryptoLogic.balanceError(fromCoin: btc, feeCoin: btc, fromAmount: "1.0", fee: .zero),
            .insufficientFunds
        )
    }

    func testBalanceErrorInsufficientGasWhenAmountFitsButFeeOverflows() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true, rawBalance: "100000000") // 1 BTC
        XCTAssertEqual(
            SwapCryptoLogic.balanceError(fromCoin: btc, feeCoin: btc, fromAmount: "1.0", fee: BigInt(1_000)),
            .insufficientGas
        )
    }

    // MARK: - balanceError — separate gas coin (ERC20)

    func testBalanceErrorNilForERC20WhenBothBalancesSufficient() {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false, rawBalance: "200000000") // 200 USDC
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true, rawBalance: "1000000000000000000") // 1 ETH
        XCTAssertNil(SwapCryptoLogic.balanceError(fromCoin: usdc, feeCoin: eth, fromAmount: "100", fee: BigInt(100_000_000_000_000)))
    }

    func testBalanceErrorInsufficientFundsForERC20WhenAmountExceedsTokenBalance() {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false, rawBalance: "50000000") // 50 USDC
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true, rawBalance: "1000000000000000000")
        XCTAssertEqual(
            SwapCryptoLogic.balanceError(fromCoin: usdc, feeCoin: eth, fromAmount: "100", fee: .zero),
            .insufficientFunds
        )
    }

    func testBalanceErrorInsufficientGasForERC20WhenGasCoinUnderfunded() {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false, rawBalance: "200000000") // 200 USDC
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true, rawBalance: "0") // 0 ETH
        XCTAssertEqual(
            SwapCryptoLogic.balanceError(fromCoin: usdc, feeCoin: eth, fromAmount: "100", fee: BigInt(100_000_000_000_000)),
            .insufficientGas
        )
    }

    // MARK: - validateForm — gating conditions

    func testValidateFormTrueWhenAllConditionsMet() {
        XCTAssertTrue(makeValidateCall())
    }

    func testValidateFormFalseWhenFromAndToCoinAreSame() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true, rawBalance: "100000000")
        XCTAssertFalse(makeValidateCall(toCoin: btc))
    }

    func testValidateFormFalseWhenFromCoinIsExample() {
        XCTAssertFalse(makeValidateCall(fromCoin: .example))
    }

    func testValidateFormFalseWhenFromAmountEmpty() {
        XCTAssertFalse(makeValidateCall(fromAmount: ""))
    }

    func testValidateFormFalseWhenQuoteNil() {
        let from = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true, rawBalance: "100000000")
        let to = makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true)
        XCTAssertFalse(SwapCryptoLogic.validateForm(
            fromCoin: from,
            toCoin: to,
            fromAmount: "0.1",
            quote: nil,
            fee: BigInt(1_000),
            toAmount: 1,
            isSufficientBalance: true,
            isLoading: false
        ))
    }

    func testValidateFormFalseWhenFeeZero() {
        XCTAssertFalse(makeValidateCall(fee: .zero))
    }

    func testValidateFormFalseWhenIsLoading() {
        XCTAssertFalse(makeValidateCall(isLoading: true))
    }

    func testValidateFormFalseWhenBalanceInsufficient() {
        XCTAssertFalse(makeValidateCall(isSufficientBalance: false))
    }

    // MARK: - Fixtures

    private func makeValidateCall(
        fromCoin: Coin? = nil,
        toCoin: Coin? = nil,
        fromAmount: String = "0.1",
        quote: SwapQuote? = nil,
        fee: BigInt = BigInt(1_000),
        toAmount: Decimal = 1,
        isSufficientBalance: Bool = true,
        isLoading: Bool = false
    ) -> Bool {
        let resolvedFrom = fromCoin ?? makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true, rawBalance: "100000000")
        let resolvedTo = toCoin ?? makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true)
        let resolvedQuote = quote ?? .thorchain(makeThorQuote())
        return SwapCryptoLogic.validateForm(
            fromCoin: resolvedFrom,
            toCoin: resolvedTo,
            fromAmount: fromAmount,
            quote: resolvedQuote,
            fee: fee,
            toAmount: toAmount,
            isSufficientBalance: isSufficientBalance,
            isLoading: isLoading
        )
    }

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool, rawBalance: String = "0") -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        let coin = Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
        coin.rawBalance = rawBalance
        return coin
    }

    private func makeThorQuote() -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: "100000000",
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
}
