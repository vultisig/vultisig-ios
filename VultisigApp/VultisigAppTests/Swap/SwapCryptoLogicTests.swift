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
        let result = SwapCryptoLogic.fee(quote: .thorchain(makeThorQuote()), thorchainFee: BigInt(7_777))
        XCTAssertEqual(result, BigInt(7_777))
    }

    func testFeeForMayachainQuoteUsesThorchainFee() {
        let result = SwapCryptoLogic.fee(quote: .mayachain(makeThorQuote()), thorchainFee: BigInt(99))
        XCTAssertEqual(result, BigInt(99))
    }

    func testFeeForOneInchQuoteUsesQuoteFee() {
        let result = SwapCryptoLogic.fee(quote: .oneinch(makeEVMQuote(), fee: BigInt(42)), thorchainFee: BigInt(123))
        XCTAssertEqual(result, BigInt(42))
    }

    func testFeeForKyberSwapQuoteUsesQuoteFee() {
        let result = SwapCryptoLogic.fee(quote: .kyberswap(makeEVMQuote(), fee: BigInt(11)), thorchainFee: .zero)
        XCTAssertEqual(result, BigInt(11))
    }

    func testFeeForLifiQuoteUsesQuoteFee() {
        let result = SwapCryptoLogic.fee(quote: .lifi(makeEVMQuote(), fee: BigInt(5), integratorFee: nil), thorchainFee: .zero)
        XCTAssertEqual(result, BigInt(5))
    }

    func testFeeForEVMQuoteWithNilFeeReturnsZero() {
        let result = SwapCryptoLogic.fee(quote: .oneinch(makeEVMQuote(), fee: nil), thorchainFee: .zero)
        XCTAssertEqual(result, .zero)
    }

    func testFeeForNilQuoteReturnsZero() {
        XCTAssertEqual(SwapCryptoLogic.fee(quote: nil, thorchainFee: .zero), .zero)
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

    // MARK: - getDefaultCoin (TokensStore fallback)

    /// When the vault holds the Sui chain but not the native SUI coin,
    /// `getDefaultCoin` falls back to `TokensStore.TokenSelectionAssets`. That
    /// curated list places a bridged ETH-on-Sui token BEFORE native SUI, so the
    /// old non-strict-weak `.sorted` comparator returned ETH. The fix must pick
    /// native SUI deterministically.
    func testGetDefaultCoinForSuiReturnsNativeSuiNotBridgedEth() throws {
        let vault = makeVaultWithValidKeys()
        let coin = try XCTUnwrap(SwapCryptoLogic.getDefaultCoin(for: .sui, vault: vault))
        XCTAssertEqual(coin.chain, .sui)
        XCTAssertEqual(coin.ticker, "SUI")
        XCTAssertTrue(coin.isNativeToken)
        XCTAssertNotEqual(coin.ticker, "ETH")
    }

    /// Sanity: the vault path still takes precedence — a vault that already
    /// holds the native coin returns that exact coin, not a TokensStore lookup.
    func testGetDefaultCoinPrefersNativeCoinFromVault() throws {
        let sui = makeCoin(.sui, ticker: "SUI", decimals: 9, isNative: true)
        let vault = makeVaultWithValidKeys(coins: [sui])
        let coin = try XCTUnwrap(SwapCryptoLogic.getDefaultCoin(for: .sui, vault: vault))
        XCTAssertTrue(coin.isNativeToken)
        XCTAssertEqual(coin.ticker, "SUI")
    }

    private func makeVaultWithValidKeys(coins: [Coin] = []) -> Vault {
        // A real 64-char hex key so CoinFactory can derive the Sui address in
        // the TokensStore-fallback branch (placeholder keys would throw).
        let pubKey = "feedf00dfeedf00dfeedf00dfeedf00dfeedf00dfeedf00dfeedf00dfeedf00d"
        let vault = Vault(name: "test-vault")
        vault.localPartyID = "test-device-123"
        vault.pubKeyECDSA = pubKey
        vault.pubKeyEdDSA = pubKey
        vault.hexChainCode = String(repeating: "0", count: 64)
        vault.coins = coins
        return vault
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
