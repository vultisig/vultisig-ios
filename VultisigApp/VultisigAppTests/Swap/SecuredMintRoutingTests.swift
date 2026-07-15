//
//  SecuredMintRoutingTests.swift
//  VultisigAppTests
//
//  Covers the inline same-underlying → SECURE+ mint routing (#4788 Phase 4):
//  the detection decision (same-underlying vs cross-asset, case-insensitive),
//  the synthetic ~1:1 display quote, and the "Mint (SECURE+)" provider label.
//  The actual SECURE+ deposit payload build (`buildSecuredMintPayload`) hits the
//  network (inbound + chain-specific) and is exercised on-device.
//

import XCTest
@testable import VultisigApp

@MainActor
final class SecuredMintRoutingTests: XCTestCase {

    private func coin(
        ticker: String,
        chain: Chain,
        contractAddress: String,
        isNative: Bool,
        address: String = "addr"
    ) -> Coin {
        let meta = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "",
            decimals: 8,
            priceProviderId: "",
            contractAddress: contractAddress,
            isNativeToken: isNative
        )
        return Coin(asset: meta, address: address, hexPublicKey: "test")
    }

    private func securedBTC() -> Coin {
        coin(ticker: "BTC", chain: .thorChain, contractAddress: "btc-btc", isNative: false, address: "thor1abc")
    }

    private func securedEthUsdc() -> Coin {
        coin(ticker: "USDC", chain: .thorChain,
             contractAddress: "eth-usdc-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", isNative: false, address: "thor1abc")
    }

    // MARK: - Detection

    func testNativeBtcToSecuredBtcIsSameUnderlying() {
        let fromBTC = coin(ticker: "BTC", chain: .bitcoin, contractAddress: "", isNative: true)
        XCTAssertTrue(SwapCryptoLogic.isSameUnderlyingSecuredMint(fromCoin: fromBTC, toCoin: securedBTC()))
    }

    func testErc20UsdcToSecuredUsdcIsSameUnderlyingCaseInsensitive() {
        // fromCoin swapAsset preserves the lowercase hex; securedAssetSymbol
        // uppercases it — the compare must be case-insensitive.
        let fromUSDC = coin(ticker: "USDC", chain: .ethereum,
                            contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", isNative: false)
        XCTAssertTrue(SwapCryptoLogic.isSameUnderlyingSecuredMint(fromCoin: fromUSDC, toCoin: securedEthUsdc()))
    }

    func testCrossAssetEthToSecuredBtcIsNotSameUnderlying() {
        let fromETH = coin(ticker: "ETH", chain: .ethereum, contractAddress: "", isNative: true)
        XCTAssertFalse(SwapCryptoLogic.isSameUnderlyingSecuredMint(fromCoin: fromETH, toCoin: securedBTC()))
    }

    func testCrossAssetRuneToSecuredUsdcIsNotSameUnderlying() {
        let fromRUNE = coin(ticker: "RUNE", chain: .thorChain, contractAddress: "", isNative: true)
        XCTAssertFalse(SwapCryptoLogic.isSameUnderlyingSecuredMint(fromCoin: fromRUNE, toCoin: securedEthUsdc()))
    }

    func testNonSecuredDestinationIsNotSameUnderlying() {
        let fromBTC = coin(ticker: "BTC", chain: .bitcoin, contractAddress: "", isNative: true)
        let plainRune = coin(ticker: "RUNE", chain: .thorChain, contractAddress: "", isNative: true)
        XCTAssertFalse(SwapCryptoLogic.isSameUnderlyingSecuredMint(fromCoin: fromBTC, toCoin: plainRune))
    }

    // MARK: - Synthetic quote

    func testSecuredMintQuoteIsApproximatelyOneToOne() {
        let quote = SwapCryptoLogic.securedMintQuote(fromAmount: 1.5, toCoin: securedBTC())
        let out = SwapCryptoLogic.toAmountDecimal(quote: quote, toCoin: securedBTC())
        XCTAssertEqual(out, 1.5)
        XCTAssertNil(quote.priceImpact, "Mint has no pool price impact")
        XCTAssertEqual(quote.totalFees, "0", "Mint carries no swap/affiliate fee")
    }

    // MARK: - Provider label

    func testProviderLabelReflectsMode() {
        var tx = SwapTransaction.example
        tx.mode = .securedMint
        XCTAssertEqual(tx.providerDisplayName, "Mint (SECURE+)")
        tx.mode = .standard
        XCTAssertEqual(tx.providerDisplayName, tx.quote.displayName)
    }

    // MARK: - Approve consent

    private func securedMintTransaction(fromCoin: Coin) -> SwapTransaction {
        let base = SwapTransaction.example
        return SwapTransaction(
            fromCoin: fromCoin,
            toCoin: base.toCoin,
            fromAmount: base.fromAmount,
            quote: base.quote,
            mode: .securedMint,
            gas: base.gas,
            gasLimit: base.gasLimit,
            thorchainFee: base.thorchainFee,
            vultDiscountBps: base.vultDiscountBps,
            referralDiscountBps: base.referralDiscountBps,
            feeCoin: base.feeCoin,
            advancedSettings: base.advancedSettings
        )
    }

    /// An ERC20 secured mint bundles a router approval, so the Verify screen must
    /// require the approval-consent checkbox — even though the synthetic quote has
    /// no router (which is what `isApproveRequired` keys off for normal swaps).
    func testErc20SecuredMintRequiresApproveConsent() {
        let usdc = coin(ticker: "USDC", chain: .ethereum,
                        contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", isNative: false)
        XCTAssertTrue(securedMintTransaction(fromCoin: usdc).isApproveRequired)
    }

    func testNativeSecuredMintDoesNotRequireApprove() {
        let btc = coin(ticker: "BTC", chain: .bitcoin, contractAddress: "", isNative: true)
        XCTAssertFalse(securedMintTransaction(fromCoin: btc).isApproveRequired)
    }

    // MARK: - Inbound resolution (offline branch)

    func testResolveInboundDestinationForThorChainSourceReturnsOwnAddress() async throws {
        // A .thorChain source needs no L1 inbound — the mint deposits from the
        // vault's own THORChain address (offline branch, no network).
        let thorSource = coin(ticker: "BTC", chain: .thorChain, contractAddress: "btc-btc",
                              isNative: false, address: "thor1vault")
        let dest = try await ThorchainRouterDepositBuilder.resolveInboundDestination(coin: thorSource)
        XCTAssertEqual(dest, "thor1vault")
    }
}
