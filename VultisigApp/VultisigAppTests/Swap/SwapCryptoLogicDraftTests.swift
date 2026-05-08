//
//  SwapCryptoLogicDraftTests.swift
//  VultisigAppTests
//
//  Per-helper coverage for the §1.5 port of SwapTransaction's instance
//  helpers into SwapCryptoLogic over SwapDraft. Each non-trivial branch
//  gets a row.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SwapCryptoLogicDraftTests: XCTestCase {

    // MARK: - Amount conversions

    func testFromAmountDecimalParsesString() {
        var draft = SwapDraft()
        draft.fromAmount = "1.5"
        XCTAssertEqual(SwapCryptoLogic.fromAmountDecimal(draft: draft), Decimal(string: "1.5"))
    }

    func testFromAmountDecimalEmptyReturnsZero() {
        let draft = SwapDraft()
        XCTAssertEqual(SwapCryptoLogic.fromAmountDecimal(draft: draft), .zero)
    }

    func testAmountInCoinDecimalScalesByCoinDecimals() {
        var draft = SwapDraft()
        draft.fromCoin = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        draft.fromAmount = "1.5"
        XCTAssertEqual(SwapCryptoLogic.amountInCoinDecimal(draft: draft), BigInt(150_000_000))
    }

    // MARK: - fee

    func testFeeForThorchainQuoteUsesThorchainFee() {
        var draft = SwapDraft()
        draft.thorchainFee = BigInt(7_777)
        draft.quote = .thorchain(makeThorQuote())
        XCTAssertEqual(SwapCryptoLogic.fee(draft: draft), BigInt(7_777))
    }

    func testFeeForMayachainQuoteUsesThorchainFee() {
        var draft = SwapDraft()
        draft.thorchainFee = BigInt(99)
        draft.quote = .mayachain(makeThorQuote())
        XCTAssertEqual(SwapCryptoLogic.fee(draft: draft), BigInt(99))
    }

    func testFeeForOneInchQuoteUsesQuoteFee() {
        var draft = SwapDraft()
        draft.thorchainFee = BigInt(123) // ignored for EVM quotes
        draft.quote = .oneinch(makeEVMQuote(), fee: BigInt(42))
        XCTAssertEqual(SwapCryptoLogic.fee(draft: draft), BigInt(42))
    }

    func testFeeForKyberSwapQuoteUsesQuoteFee() {
        var draft = SwapDraft()
        draft.quote = .kyberswap(makeEVMQuote(), fee: BigInt(11))
        XCTAssertEqual(SwapCryptoLogic.fee(draft: draft), BigInt(11))
    }

    func testFeeForLifiQuoteUsesQuoteFee() {
        var draft = SwapDraft()
        draft.quote = .lifi(makeEVMQuote(), fee: BigInt(5), integratorFee: nil)
        XCTAssertEqual(SwapCryptoLogic.fee(draft: draft), BigInt(5))
    }

    func testFeeForEVMQuoteWithNilFeeReturnsZero() {
        var draft = SwapDraft()
        draft.quote = .oneinch(makeEVMQuote(), fee: nil)
        XCTAssertEqual(SwapCryptoLogic.fee(draft: draft), .zero)
    }

    func testFeeForNilQuoteReturnsZero() {
        let draft = SwapDraft()
        XCTAssertEqual(SwapCryptoLogic.fee(draft: draft), .zero)
    }

    // MARK: - inboundFeeDecimal

    func testInboundFeeDecimalNilQuoteReturnsNil() {
        let draft = SwapDraft()
        XCTAssertNil(SwapCryptoLogic.inboundFeeDecimal(draft: draft))
    }

    func testInboundFeeDecimalThorchainDelegatesToQuote() {
        var draft = SwapDraft()
        draft.toCoin = makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true)
        // fees.total = 1_000 → 1_000 / 10^8 = 0.00001
        draft.quote = .thorchain(makeThorQuote(feesTotal: "1000"))
        let result = SwapCryptoLogic.inboundFeeDecimal(draft: draft)
        XCTAssertEqual(result, Decimal(string: "0.00001"))
    }

    // MARK: - toAmountDecimal

    func testToAmountDecimalNilQuoteReturnsZero() {
        let draft = SwapDraft()
        XCTAssertEqual(SwapCryptoLogic.toAmountDecimal(draft: draft), .zero)
    }

    func testToAmountDecimalThorchainDividesByMultiplier() {
        var draft = SwapDraft()
        draft.toCoin = makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true)
        draft.quote = .thorchain(makeThorQuote(expectedAmountOut: "100000000"))
        // 100_000_000 / 10^8 = 1
        XCTAssertEqual(SwapCryptoLogic.toAmountDecimal(draft: draft), 1)
    }

    func testToAmountDecimalOneInchUsesDstAmount() {
        var draft = SwapDraft()
        draft.toCoin = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        draft.quote = .oneinch(makeEVMQuote(dstAmount: "1000000000000000000"), fee: nil)
        // 10^18 / 10^18 = 1
        XCTAssertEqual(SwapCryptoLogic.toAmountDecimal(draft: draft), 1)
    }

    // MARK: - router

    func testRouterNilWhenQuoteNil() {
        let draft = SwapDraft()
        XCTAssertNil(SwapCryptoLogic.router(draft: draft))
    }

    func testRouterFromThorchainQuote() {
        var draft = SwapDraft()
        draft.quote = .thorchain(makeThorQuote(router: "0xRouter"))
        XCTAssertEqual(SwapCryptoLogic.router(draft: draft), "0xRouter")
    }

    func testRouterFromEVMQuoteUsesTxTo() {
        var draft = SwapDraft()
        draft.quote = .oneinch(makeEVMQuote(toAddress: "0xAggregator"), fee: nil)
        XCTAssertEqual(SwapCryptoLogic.router(draft: draft), "0xAggregator")
    }

    // MARK: - isApproveRequired

    func testIsApproveRequiredFalseForNativeCoin() {
        var draft = SwapDraft()
        draft.fromCoin = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        draft.quote = .oneinch(makeEVMQuote(toAddress: "0xRouter"), fee: nil)
        XCTAssertFalse(SwapCryptoLogic.isApproveRequired(draft: draft))
    }

    func testIsApproveRequiredFalseForNonEVMToken() {
        var draft = SwapDraft()
        draft.fromCoin = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: false)
        draft.quote = .thorchain(makeThorQuote(router: "0xRouter"))
        XCTAssertFalse(SwapCryptoLogic.isApproveRequired(draft: draft))
    }

    func testIsApproveRequiredTrueForERC20WithRouter() {
        var draft = SwapDraft()
        draft.fromCoin = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        draft.quote = .oneinch(makeEVMQuote(toAddress: "0xRouter"), fee: nil)
        XCTAssertTrue(SwapCryptoLogic.isApproveRequired(draft: draft))
    }

    func testIsApproveRequiredFalseForERC20WithoutQuote() {
        var draft = SwapDraft()
        draft.fromCoin = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        XCTAssertFalse(SwapCryptoLogic.isApproveRequired(draft: draft))
    }

    // MARK: - isDeposit

    func testIsDepositTrueForMayaChain() {
        var draft = SwapDraft()
        draft.fromCoin = makeCoin(.mayaChain, ticker: "CACAO", decimals: 10, isNative: true)
        XCTAssertTrue(SwapCryptoLogic.isDeposit(draft: draft))
    }

    func testIsDepositFalseForThorChain() {
        var draft = SwapDraft()
        draft.fromCoin = makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true)
        XCTAssertFalse(SwapCryptoLogic.isDeposit(draft: draft))
    }

    // MARK: - isAffiliate

    func testIsAffiliateAlwaysTrue() {
        XCTAssertTrue(SwapCryptoLogic.isAffiliate(draft: SwapDraft()))
    }

    // MARK: - Fixtures

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        return Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
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
