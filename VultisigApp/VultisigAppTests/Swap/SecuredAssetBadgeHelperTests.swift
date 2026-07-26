//
//  SecuredAssetBadgeHelperTests.swift
//  VultisigAppTests
//
//  Covers the `CoinMeta` overloads of `THORChainHelper.isSecuredAsset` /
//  `securedAssetChain` that drive the swap picker's "Secured" badge + L1-chain
//  label (`SwapCoinCell`). The picker renders from `CoinMeta`, so the detection
//  must agree with the existing `Coin`-based path.
//

import XCTest
@testable import VultisigApp

final class SecuredAssetBadgeHelperTests: XCTestCase {

    private func meta(
        ticker: String,
        chain: Chain,
        contractAddress: String,
        isNativeToken: Bool
    ) -> CoinMeta {
        CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "",
            decimals: 8,
            priceProviderId: "",
            contractAddress: contractAddress,
            isNativeToken: isNativeToken
        )
    }

    func testSecuredEvmTokenIsDetectedWithL1Chain() {
        let usdc = meta(ticker: "USDC", chain: .thorChain,
                        contractAddress: "eth-usdc-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                        isNativeToken: false)
        XCTAssertTrue(THORChainHelper.isSecuredAsset(coinMeta: usdc))
        XCTAssertEqual(THORChainHelper.securedAssetChain(coinMeta: usdc), "ETH")
    }

    func testSecuredNativeFormIsDetected() {
        let btc = meta(ticker: "BTC", chain: .thorChain, contractAddress: "btc-btc", isNativeToken: false)
        XCTAssertTrue(THORChainHelper.isSecuredAsset(coinMeta: btc))
        XCTAssertEqual(THORChainHelper.securedAssetChain(coinMeta: btc), "BTC")
    }

    func testNativeRuneIsNotSecured() {
        let rune = meta(ticker: "RUNE", chain: .thorChain, contractAddress: "", isNativeToken: true)
        XCTAssertFalse(THORChainHelper.isSecuredAsset(coinMeta: rune))
    }

    func testMergedAssetDenomIsNotSecured() {
        // `x/`-prefixed denoms are merged assets, not secured assets.
        let merged = meta(ticker: "RUJI", chain: .thorChain, contractAddress: "x/ruji", isNativeToken: false)
        XCTAssertFalse(THORChainHelper.isSecuredAsset(coinMeta: merged))
    }

    func testNonThorChainTokenIsNotSecured() {
        let ethUsdc = meta(ticker: "USDC", chain: .ethereum,
                           contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                           isNativeToken: false)
        XCTAssertFalse(THORChainHelper.isSecuredAsset(coinMeta: ethUsdc))
    }
}
