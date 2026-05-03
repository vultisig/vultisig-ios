//
//  MayaPoolPriceTests.swift
//  VultisigAppTests
//
//  Verifies the MAYA.MAYA pool-derived pricing pipeline added in PR #4104
//  (issue #4280). Targets the pure `calculateMayaPoolPrice` computation so
//  the math is checked without hitting the live mayanode endpoint.
//

import XCTest
@testable import VultisigApp

final class MayaPoolPriceTests: XCTestCase {

    private let mayaCoin = CoinMeta(
        chain: .mayaChain,
        ticker: "MAYA",
        logo: "maya",
        decimals: 4,
        priceProviderId: "",
        contractAddress: "maya",
        isNativeToken: false
    )

    // MARK: - calculateMayaPoolPrice

    func test_calculateMayaPoolPrice_equalDepth_returnsCacaoPriceUSD() {
        // 100 CACAO (10 decimals) vs 100 MAYA (4 decimals) → 1 CACAO per MAYA.
        let pool = MAYAChainPoolResponse(
            balanceCacao: "1000000000000",
            balanceAsset: "1000000"
        )

        let price = CryptoPriceService.shared.calculateMayaPoolPrice(
            pool: pool,
            cacaoPriceUSD: 0.5,
            coins: [mayaCoin],
            assetName: "MAYA.MAYA"
        )

        XCTAssertEqual(price, 0.5, accuracy: 1e-9)
    }

    func test_calculateMayaPoolPrice_scarceAsset_doublesPrice() {
        // 200 CACAO vs 100 MAYA → 2 CACAO per MAYA.
        let pool = MAYAChainPoolResponse(
            balanceCacao: "2000000000000",
            balanceAsset: "1000000"
        )

        let price = CryptoPriceService.shared.calculateMayaPoolPrice(
            pool: pool,
            cacaoPriceUSD: 0.5,
            coins: [mayaCoin],
            assetName: "MAYA.MAYA"
        )

        XCTAssertEqual(price, 1.0, accuracy: 1e-9)
    }

    func test_calculateMayaPoolPrice_abundantAsset_lowersPrice() {
        // 100 CACAO vs 1000 MAYA → 0.1 CACAO per MAYA.
        let pool = MAYAChainPoolResponse(
            balanceCacao: "1000000000000",
            balanceAsset: "10000000"
        )

        let price = CryptoPriceService.shared.calculateMayaPoolPrice(
            pool: pool,
            cacaoPriceUSD: 0.5,
            coins: [mayaCoin],
            assetName: "MAYA.MAYA"
        )

        XCTAssertEqual(price, 0.05, accuracy: 1e-9)
    }

    func test_calculateMayaPoolPrice_zeroAssetBalance_returnsZero() {
        let pool = MAYAChainPoolResponse(
            balanceCacao: "1000000000000",
            balanceAsset: "0"
        )

        let price = CryptoPriceService.shared.calculateMayaPoolPrice(
            pool: pool,
            cacaoPriceUSD: 0.5,
            coins: [mayaCoin],
            assetName: "MAYA.MAYA"
        )

        XCTAssertEqual(price, 0.0)
    }

    func test_calculateMayaPoolPrice_nonNumericBalances_returnsZero() {
        let pool = MAYAChainPoolResponse(
            balanceCacao: "not-a-number",
            balanceAsset: "1000000"
        )

        let price = CryptoPriceService.shared.calculateMayaPoolPrice(
            pool: pool,
            cacaoPriceUSD: 0.5,
            coins: [mayaCoin],
            assetName: "MAYA.MAYA"
        )

        XCTAssertEqual(price, 0.0)
    }

    func test_calculateMayaPoolPrice_unknownTicker_fallsBackToFourDecimals() {
        // Asset not present in `coins` — calculator must fall back to 4 decimals
        // (matches all current Maya pool assets in TokensStore).
        let pool = MAYAChainPoolResponse(
            balanceCacao: "1000000000000",
            balanceAsset: "1000000"
        )

        let price = CryptoPriceService.shared.calculateMayaPoolPrice(
            pool: pool,
            cacaoPriceUSD: 1.0,
            coins: [],
            assetName: "MAYA.AZTEC"
        )

        // 100 CACAO vs 100 AZTEC at 4-decimal fallback → 1 CACAO each.
        XCTAssertEqual(price, 1.0, accuracy: 1e-9)
    }

    func test_calculateMayaPoolPrice_decodesFromMayanodeJSONShape() throws {
        // Defends against accidental rename of the `balance_cacao` / `balance_asset`
        // JSON keys returned by https://mayanode.mayachain.info/mayachain/pool/MAYA.MAYA
        let json = #"""
        {
            "balance_cacao": "1000000000000",
            "balance_asset": "1000000"
        }
        """#.data(using: .utf8)!

        let pool = try JSONDecoder().decode(MAYAChainPoolResponse.self, from: json)

        XCTAssertEqual(pool.balanceCacao, "1000000000000")
        XCTAssertEqual(pool.balanceAsset, "1000000")

        let price = CryptoPriceService.shared.calculateMayaPoolPrice(
            pool: pool,
            cacaoPriceUSD: 0.5,
            coins: [mayaCoin],
            assetName: "MAYA.MAYA"
        )
        XCTAssertEqual(price, 0.5, accuracy: 1e-9)
    }

    // MARK: - Routing — guards against regressions in the rate-lookup identifier

    func test_rateProvider_routesMayaTokenToContractIdentifier() {
        // The pricing pipeline saves Rate(crypto: "maya"); RateProvider must
        // resolve the same identifier when the UI looks up the rate.
        let cryptoId = RateProvider.cryptoId(for: mayaCoin)

        switch cryptoId {
        case .contract(let id):
            XCTAssertEqual(id, "maya", "MAYA token must lookup by contract \"maya\" so saved rates round-trip")
        case .priceProvider:
            XCTFail("MAYA token must not route through priceProvider — its providerId is empty")
        }
    }

    func test_tokensStore_mayaCoinMetadataMatchesPipelineExpectations() throws {
        // Locks the TokensStore values that the pricing pipeline depends on:
        // contractAddress "maya" (used as Rate.crypto and asset lookup),
        // chain .mayaChain (routes to fetchMayaChainPoolPrices), 4 decimals
        // (used by calculateMayaPoolPrice), and an empty priceProviderId
        // (forces the .contract branch in RateProvider.cryptoId).
        let maya = try XCTUnwrap(TokensStore.TokenSelectionAssets.first(where: {
            $0.chain == .mayaChain && $0.ticker == "MAYA"
        }))

        XCTAssertEqual(maya.contractAddress, "maya")
        XCTAssertEqual(maya.decimals, 4)
        XCTAssertEqual(maya.priceProviderId, "")
        XCTAssertFalse(maya.isNativeToken)
    }
}
