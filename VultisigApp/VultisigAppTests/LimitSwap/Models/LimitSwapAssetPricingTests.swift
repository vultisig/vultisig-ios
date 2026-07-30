//
//  LimitSwapAssetPricingTests.swift
//  VultisigAppTests
//
//  The price-provider id a limit asset carries, and the CoinMeta it hands to
//  the shared market-data layer.
//

@testable import VultisigApp
import Foundation
import XCTest

final class LimitSwapAssetPricingTests: XCTestCase {

    // MARK: - The production path

    func testAssetBuiltFromACoinCarriesItsPriceProviderId() {
        // The only construction the app itself uses. Without the id the asset
        // resolves to no market-data source at all, and the chart silently never
        // appears for exactly the native assets limit orders are written on.
        let coin = Coin(
            asset: CoinMeta(
                chain: .bitcoin,
                ticker: "BTC",
                logo: "btc",
                decimals: 8,
                priceProviderId: "bitcoin",
                contractAddress: "",
                isNativeToken: true
            ),
            address: "bc1qexampleaddress",
            hexPublicKey: "0000"
        )

        let asset = LimitSwapAsset(coin: coin)

        XCTAssertEqual(asset.priceProviderId, "bitcoin")
        XCTAssertEqual(asset.coinMeta.priceProviderId, "bitcoin")
    }

    func testANativeAssetResolvesToAMarketDataSource() {
        // The regression this field exists for: a native asset has no contract
        // address, so the id is the ONLY thing that can resolve it.
        let asset = LimitSwapAsset(
            chain: .bitcoin,
            ticker: "BTC",
            decimals: 8,
            contractAddress: "",
            isNativeToken: true,
            priceProviderId: "bitcoin"
        )

        XCTAssertEqual(MarketDataService.resolveSource(for: asset.coinMeta), .id("bitcoin"))
    }

    func testANativeAssetWithoutAnIdResolvesToNothing() {
        // Pins the failure mode rather than leaving it to be rediscovered: this
        // is what the whole feature looked like before the id was carried.
        let asset = LimitSwapAsset(
            chain: .bitcoin,
            ticker: "BTC",
            decimals: 8,
            contractAddress: "",
            isNativeToken: true
        )

        XCTAssertNil(MarketDataService.resolveSource(for: asset.coinMeta))
    }

    func testAnEvmTokenStillResolvesByContractWithoutAnId() {
        // Tokens were never broken — they route on the contract address — so the
        // new field must not have changed their path.
        let asset = LimitSwapAsset(
            chain: .ethereum,
            ticker: "USDC",
            decimals: 6,
            contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
            isNativeToken: false
        )

        XCTAssertEqual(
            MarketDataService.resolveSource(for: asset.coinMeta),
            .contract(platform: "ethereum", address: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")
        )
    }

    // MARK: - The rest of the asset is untouched

    func testCarryingTheIdDoesNotDisturbTheMemoSpelling() {
        // The memo asset string is fund-safety critical and must not depend on
        // anything added for display or pricing.
        let withId = LimitSwapAsset(
            chain: .bitcoin, ticker: "BTC", decimals: 8,
            contractAddress: "", isNativeToken: true, priceProviderId: "bitcoin"
        )
        let withoutId = LimitSwapAsset(
            chain: .bitcoin, ticker: "BTC", decimals: 8,
            contractAddress: "", isNativeToken: true
        )

        XCTAssertEqual(withId.memoSymbol, withoutId.memoSymbol)
        XCTAssertEqual(withId.cancelMemoSymbol, withoutId.cancelMemoSymbol)
    }
}
