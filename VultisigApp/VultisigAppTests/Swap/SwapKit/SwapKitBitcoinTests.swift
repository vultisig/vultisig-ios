//
//  SwapKitBitcoinTests.swift
//  VultisigAppTests
//
//  Phase 2 Bitcoin coverage: quote-decode + `/v3/swap` PSBT-decode against
//  the real-balance fixtures captured by the Phase 0 spike, plus the new
//  `SwapPayloadBuilder.buildSwapKitPSBTPayload` structural assertion that
//  the `.psbt` route flows through the new `SwapPayload.swapkit` variant
//  with bytes that round-trip back to the original PSBT.
//
//  Chainflip BTC fixture is intentionally absent — the spike couldn't
//  capture a /v3/swap fixture for that provider (different validation
//  gate). PSBT decoder is structural; Chainflip will work the same way at
//  runtime since all observed BTC providers return the uniform PSBT shape.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SwapKitBitcoinTests: XCTestCase {

    // MARK: - Quote decode

    func testBitcoinQuoteFixtureDecodesAllThreeProviders() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitQuoteResponse.self,
            from: "v3-real-btc-all-quote"
        )
        XCTAssertEqual(response.routes.count, 3)
        let providers = response.routes.map(\.providers)
        XCTAssertEqual(providers, [["NEAR"], ["FLASHNET"], ["GARDEN"]])
        XCTAssertNil(response.routes[0].meta.txType, "txType is null at quote stage")
    }

    func testBitcoinQuoteSurvivesClientFilter() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitQuoteResponse.self,
            from: "v3-real-btc-all-quote"
        )
        let filtered = SwapKitService.filterRoutes(response.routes)
        XCTAssertEqual(
            filtered.count,
            response.routes.count,
            "BTC routes are single-hop NEAR/FLASHNET/GARDEN — no THORChain/Maya filter hits"
        )
    }

    // MARK: - PSBT swap decode — three fixtures share the same wire shape

    func testNearPSBTSwapResponseDecodes() throws {
        try assertPSBTSwapFixture(
            name: "v3-real-btc-all-swap",
            expectedProvider: "NEAR",
            expectedTarget: "bc1q0w42efzvjyg44c6aec6ppaee2530rsd2036hrp",
            expectedInbound: "bc1q0w42efzvjyg44c6aec6ppaee2530rsd2036hrp"
        )
    }

    func testFlashnetPSBTSwapResponseDecodes() throws {
        try assertPSBTSwapFixture(
            name: "v3-real-btc-FLASHNET-swap",
            expectedProvider: "FLASHNET",
            expectedTarget: "bc1pfyznz04qpydjl7ucuer8k2ppugfv3hjskn93gmm7a9c4u80scxcq5tukqe",
            expectedInbound: "bc1pfyznz04qpydjl7ucuer8k2ppugfv3hjskn93gmm7a9c4u80scxcq5tukqe"
        )
    }

    func testGardenPSBTSwapResponseDecodes() throws {
        try assertPSBTSwapFixture(
            name: "v3-real-btc-GARDEN-swap",
            expectedProvider: "GARDEN",
            expectedTarget: "bc1p5yegfhq59x3uxhz7rptlpqfzd3z2dhaqetcsqk7ypx8v2g63yrrscxtw6w",
            expectedInbound: nil
        )
    }

    // MARK: - SwapPayloadBuilder structural coverage

    func testPSBTPayloadBuilderRoundTripsBase64Bytes() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-btc-all-swap"
        )
        guard case let .psbt(base64) = response.tx else {
            XCTFail("Expected PSBT tx variant")
            return
        }
        let from = makeBtcCoin()
        let to = makeUsdcCoin()
        let payload = try SwapCryptoLogic.buildSwapKitPSBTPayload(
            fromCoin: from,
            toCoin: to,
            fromAmountInCoin: BigInt(500_000),
            toAmountDecimal: Decimal(string: "385.796992") ?? 0,
            base64PSBT: base64,
            swapResponse: response
        )
        XCTAssertEqual(payload.txType, "PSBT")
        XCTAssertEqual(payload.targetAddress, response.targetAddress)
        XCTAssertEqual(payload.subProvider, response.subProvider)
        XCTAssertEqual(payload.swapID, response.swapId)
        XCTAssertEqual(payload.inboundAddress, response.inboundAddress)
        XCTAssertNil(payload.memo, "SwapKit V3 BTC routes carry no memo")
        XCTAssertEqual(
            payload.txPayload.base64EncodedString(),
            base64,
            "tx_payload bytes must round-trip back to the original SwapKit PSBT"
        )
    }

    func testPSBTPayloadBuilderRejectsInvalidBase64() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-btc-all-swap"
        )
        let from = makeBtcCoin()
        let to = makeUsdcCoin()
        XCTAssertThrowsError(
            try SwapCryptoLogic.buildSwapKitPSBTPayload(
                fromCoin: from,
                toCoin: to,
                fromAmountInCoin: BigInt(1),
                toAmountDecimal: 0,
                base64PSBT: "@@not-base64@@",
                swapResponse: response
            )
        )
    }

    func testEvmQuoteBuilderRejectsPSBTResponse() throws {
        // `buildEVMQuoteFromSwapKit` is the EVM/Solana-only path. A PSBT
        // response that reaches it indicates a dispatch bug — surface a
        // typed error so future regressions show up here.
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-btc-all-swap"
        )
        XCTAssertThrowsError(try SwapCryptoLogic.buildEVMQuoteFromSwapKit(swapResponse: response)) { error in
            guard case SwapKitError.unsupportedTxType(let txType) = error else {
                XCTFail("Expected unsupportedTxType, got \(error)")
                return
            }
            XCTAssertEqual(txType, "PSBT")
        }
    }

    // MARK: - Helpers

    private func assertPSBTSwapFixture(
        name: String,
        expectedProvider: String,
        expectedTarget: String,
        expectedInbound: String?
    ) throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: name
        )
        XCTAssertEqual(response.meta.txType, "PSBT")
        XCTAssertEqual(response.subProvider, expectedProvider)
        XCTAssertEqual(response.targetAddress, expectedTarget)
        XCTAssertEqual(response.inboundAddress, expectedInbound)
        XCTAssertNil(response.approvalTx, "BTC routes never produce approvalTx")
        guard case let .psbt(base64) = response.tx else {
            XCTFail("Expected PSBT tx variant for \(name)")
            return
        }
        XCTAssertTrue(
            base64.hasPrefix("cHNidP8B"),
            "Base64-encoded PSBT must start with PSBT magic bytes (0x70736274ff)"
        )
        XCTAssertGreaterThan(base64.count, 400, "Observed PSBT lengths cluster around 480 chars")
        XCTAssertNotNil(Data(base64Encoded: base64), "tx must be valid base64")
    }

    private func makeBtcCoin() -> Coin {
        let asset = CoinMeta.make(
            chain: .bitcoin,
            ticker: "BTC",
            decimals: 8,
            isNativeToken: true
        )
        return Coin(asset: asset, address: "bc1q-test-address", hexPublicKey: "")
    }

    private func makeUsdcCoin() -> Coin {
        let asset = CoinMeta.make(
            chain: .ethereum,
            ticker: "USDC",
            decimals: 6,
            isNativeToken: false
        )
        return Coin(asset: asset, address: "0xtest-usdc-address", hexPublicKey: "")
    }
}
