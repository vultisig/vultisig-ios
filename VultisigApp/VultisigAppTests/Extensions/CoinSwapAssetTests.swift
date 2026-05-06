//
//  CoinSwapAssetTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

@MainActor
final class CoinSwapAssetTests: XCTestCase {

    func testSwapAssetReturnsRawThorchainSecuredUSDCDenom() {
        let denom = "eth-usdc-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
        let coin = makeCoin(
            ticker: "USDC",
            chain: .thorChain,
            contractAddress: denom,
            isNative: false
        )

        XCTAssertEqual(coin.swapAsset, denom)
    }

    func testSwapAssetReturnsRawThorchainBaseSecuredAssetDenoms() {
        let securedAssets = [
            ("BTC", "btc-btc"),
            ("ETH", "eth-eth"),
            ("LTC", "ltc-ltc"),
            ("DOGE", "doge-doge"),
            ("AVAX", "avax-avax"),
            ("BNB", "bsc-bnb")
        ]

        securedAssets.forEach { ticker, denom in
            let coin = makeCoin(
                ticker: ticker,
                chain: .thorChain,
                contractAddress: denom,
                isNative: false
            )

            XCTAssertEqual(coin.swapAsset, denom)
        }
    }

    func testSwapAssetKeepsThorchainNonSecuredTokenAsThorTicker() {
        let coin = makeCoin(
            ticker: "KUJI",
            chain: .thorChain,
            contractAddress: "thor.kuji",
            isNative: false
        )

        XCTAssertEqual(coin.swapAsset, "THOR.KUJI")
    }

    private func makeCoin(
        ticker: String,
        chain: Chain,
        contractAddress: String,
        isNative: Bool
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
        return Coin(asset: meta, address: "test", hexPublicKey: "test")
    }
}
