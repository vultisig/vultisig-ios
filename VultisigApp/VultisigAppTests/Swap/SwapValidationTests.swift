//
//  SwapValidationTests.swift
//  VultisigAppTests
//
//  Coverage for the §1.1+§1.2 port of swap-validation logic to SwapDraft —
//  feeCoin, balanceError, isSufficientBalance, validateForm. Branching by
//  same-coin vs separate-gas-coin and by each gating condition.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SwapValidationTests: XCTestCase {

    // MARK: - feeCoin

    func testFeeCoinReturnsFromCoinWhenNative() {
        var draft = SwapDraft()
        draft.fromCoin = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        XCTAssertEqual(SwapCryptoLogic.feeCoin(draft: draft), draft.fromCoin)
    }

    func testFeeCoinReturnsNativeSiblingForERC20() {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        var draft = SwapDraft()
        draft.fromCoin = usdc
        draft.fromCoins = [usdc, eth]
        XCTAssertEqual(SwapCryptoLogic.feeCoin(draft: draft), eth)
    }

    func testFeeCoinFallsBackToFromCoinWhenNoNativeSibling() {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        var draft = SwapDraft()
        draft.fromCoin = usdc
        draft.fromCoins = [usdc] // no ETH sibling
        XCTAssertEqual(SwapCryptoLogic.feeCoin(draft: draft), usdc)
    }

    // MARK: - balanceError — same-coin pays for amount + gas

    func testBalanceErrorNilWhenAmountPlusFeeFits() {
        var draft = SwapDraft()
        draft.fromCoin = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true, rawBalance: "100000000") // 1 BTC
        draft.fromAmount = "0.5"
        draft.thorchainFee = BigInt(1_000)
        draft.quote = .thorchain(makeThorQuote())
        XCTAssertNil(SwapCryptoLogic.balanceError(draft: draft))
    }

    func testBalanceErrorInsufficientFundsWhenAmountAlreadyExceedsBalance() {
        var draft = SwapDraft()
        draft.fromCoin = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true, rawBalance: "50000000") // 0.5 BTC
        draft.fromAmount = "1.0"
        draft.thorchainFee = .zero
        draft.quote = .thorchain(makeThorQuote())
        XCTAssertEqual(SwapCryptoLogic.balanceError(draft: draft), .insufficientFunds)
    }

    func testBalanceErrorInsufficientGasWhenAmountFitsButFeeOverflows() {
        var draft = SwapDraft()
        draft.fromCoin = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true, rawBalance: "100000000") // 1 BTC
        draft.fromAmount = "1.0"
        draft.thorchainFee = BigInt(1_000) // tiny fee, but amount already at the edge
        draft.quote = .thorchain(makeThorQuote())
        XCTAssertEqual(SwapCryptoLogic.balanceError(draft: draft), .insufficientGas)
    }

    // MARK: - balanceError — separate gas coin (ERC20)

    func testBalanceErrorNilForERC20WhenBothBalancesSufficient() {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false, rawBalance: "200000000") // 200 USDC
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true, rawBalance: "1000000000000000000") // 1 ETH
        var draft = SwapDraft()
        draft.fromCoin = usdc
        draft.fromCoins = [usdc, eth]
        draft.fromAmount = "100"
        draft.quote = .oneinch(makeEVMQuote(), fee: BigInt(100_000_000_000_000)) // 0.0001 ETH
        XCTAssertNil(SwapCryptoLogic.balanceError(draft: draft))
    }

    func testBalanceErrorInsufficientFundsForERC20WhenAmountExceedsTokenBalance() {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false, rawBalance: "50000000") // 50 USDC
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true, rawBalance: "1000000000000000000")
        var draft = SwapDraft()
        draft.fromCoin = usdc
        draft.fromCoins = [usdc, eth]
        draft.fromAmount = "100"
        draft.quote = .oneinch(makeEVMQuote(), fee: BigInt(0))
        XCTAssertEqual(SwapCryptoLogic.balanceError(draft: draft), .insufficientFunds)
    }

    func testBalanceErrorInsufficientGasForERC20WhenGasCoinUnderfunded() {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false, rawBalance: "200000000") // 200 USDC
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true, rawBalance: "0") // 0 ETH
        var draft = SwapDraft()
        draft.fromCoin = usdc
        draft.fromCoins = [usdc, eth]
        draft.fromAmount = "100"
        draft.quote = .oneinch(makeEVMQuote(), fee: BigInt(100_000_000_000_000))
        XCTAssertEqual(SwapCryptoLogic.balanceError(draft: draft), .insufficientGas)
    }

    // MARK: - validateForm — gating conditions

    func testValidateFormTrueWhenAllConditionsMet() {
        let draft = makeValidDraft()
        XCTAssertTrue(SwapCryptoLogic.validateForm(draft: draft, isLoading: false))
    }

    func testValidateFormFalseWhenFromAndToCoinAreSame() {
        var draft = makeValidDraft()
        draft.toCoin = draft.fromCoin
        XCTAssertFalse(SwapCryptoLogic.validateForm(draft: draft, isLoading: false))
    }

    func testValidateFormFalseWhenFromCoinIsExample() {
        var draft = makeValidDraft()
        draft.fromCoin = .example
        XCTAssertFalse(SwapCryptoLogic.validateForm(draft: draft, isLoading: false))
    }

    func testValidateFormFalseWhenFromAmountEmpty() {
        var draft = makeValidDraft()
        draft.fromAmount = ""
        XCTAssertFalse(SwapCryptoLogic.validateForm(draft: draft, isLoading: false))
    }

    func testValidateFormFalseWhenQuoteNil() {
        var draft = makeValidDraft()
        draft.quote = nil
        XCTAssertFalse(SwapCryptoLogic.validateForm(draft: draft, isLoading: false))
    }

    func testValidateFormFalseWhenFeeZero() {
        var draft = makeValidDraft()
        draft.thorchainFee = .zero
        XCTAssertFalse(SwapCryptoLogic.validateForm(draft: draft, isLoading: false))
    }

    func testValidateFormFalseWhenIsLoading() {
        let draft = makeValidDraft()
        XCTAssertFalse(SwapCryptoLogic.validateForm(draft: draft, isLoading: true))
    }

    func testValidateFormFalseWhenBalanceInsufficient() {
        var draft = makeValidDraft()
        draft.fromAmount = "9999"
        XCTAssertFalse(SwapCryptoLogic.validateForm(draft: draft, isLoading: false))
    }

    // MARK: - Fixtures

    private func makeValidDraft() -> SwapDraft {
        var draft = SwapDraft()
        draft.fromCoin = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true, rawBalance: "100000000") // 1 BTC
        draft.toCoin = makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true)
        draft.fromAmount = "0.1"
        draft.thorchainFee = BigInt(1_000)
        draft.quote = .thorchain(makeThorQuote(expectedAmountOut: "100000000"))
        return draft
    }

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool, rawBalance: String = "0") -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        let coin = Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
        coin.rawBalance = rawBalance
        return coin
    }

    private func makeThorQuote(
        expectedAmountOut: String = "100000000",
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
        dstAmount: String = "100000000",
        toAddress: String = "0xTo"
    ) -> EVMQuote {
        EVMQuote(
            dstAmount: dstAmount,
            tx: EVMQuote.Transaction(
                from: "0xFrom",
                to: toAddress,
                data: "0x",
                value: "0",
                gasPrice: "0",
                gas: 0
            )
        )
    }
}
