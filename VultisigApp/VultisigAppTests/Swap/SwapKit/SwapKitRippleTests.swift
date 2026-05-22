//
//  SwapKitRippleTests.swift
//  VultisigAppTests
//
//  XRP source via SwapKit NEAR-Intents: deposit-only flow modelled on
//  Cardano. Decoder accepts `meta.txType: "XRP"` (canonical) and `"RIPPLE"`
//  (defensive); the response surfaces a `resolvedDestinationTag` walking
//  three sources in precedence:
//
//    1. Top-level `destinationTag` field
//    2. `meta.destinationTag`
//    3. `?dt=` or `|` suffix on `targetAddress`
//
//  Tests pin all three sources individually plus the precedence order.
//  XRP-as-source today (NEAR) returns no tag — every probe in the spike
//  hit Case A (bare r-address). The defensive plumbing protects against
//  a future Chainflip shared-vault flip where missing the tag silently
//  misroutes funds.
//

import BigInt
import Foundation
import XCTest
@testable import VultisigApp

@MainActor
final class SwapKitRippleTests: XCTestCase {

    // MARK: - Real fixture decode

    func testRealXrpSwapFixtureDecodesAsDepositOnly() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-xrp-swap"
        )
        XCTAssertEqual(response.meta.txType, "XRP")
        XCTAssertEqual(response.providers, ["NEAR"])
        XCTAssertEqual(response.subProvider, "NEAR")
        guard case .rippleDepositOnly = response.tx else {
            return XCTFail("expected .rippleDepositOnly, got \(response.tx)")
        }
        XCTAssertEqual(response.targetAddress, "rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh")
        XCTAssertEqual(response.inboundAddress, response.targetAddress)
        XCTAssertNil(response.resolvedDestinationTag, "Real NEAR XRP routes today return no destination tag")
        XCTAssertEqual(response.resolvedTargetAddress, response.targetAddress)
    }

    // MARK: - Destination tag — Case A (no tag anywhere)

    func testRippleResolvedTagIsNilWhenAbsent() throws {
        let json = makeResponseJSON(targetAddress: "rXyz", topLevelTag: nil, metaTag: nil)
        let response = try decodeResponse(json: json)
        XCTAssertNil(response.resolvedDestinationTag)
        XCTAssertEqual(response.resolvedTargetAddress, "rXyz")
    }

    // MARK: - Destination tag — Case B (suffix on targetAddress)

    func testRippleResolvedTagFromDtSuffix() throws {
        let json = makeResponseJSON(targetAddress: "rXyz?dt=12345", topLevelTag: nil, metaTag: nil)
        let response = try decodeResponse(json: json)
        XCTAssertEqual(response.resolvedDestinationTag, 12345)
        XCTAssertEqual(response.resolvedTargetAddress, "rXyz")
    }

    func testRippleResolvedTagFromDtSuffixWithExtraQueryParams() throws {
        // Multi-param query: `?dt=N&memo=foo` — the tag extractor must
        // walk the parameters and find `dt=N`, not just match a
        // `dt=`-prefixed suffix at end-of-string. Regression pin for the
        // query-string parser fix.
        let json = makeResponseJSON(targetAddress: "rXyz?dt=12345&memo=foo", topLevelTag: nil, metaTag: nil)
        let response = try decodeResponse(json: json)
        XCTAssertEqual(response.resolvedDestinationTag, 12345)
        XCTAssertEqual(response.resolvedTargetAddress, "rXyz")
    }

    func testRippleResolvedTagFromDtSuffixAfterOtherParams() throws {
        // `dt` not first: `?memo=foo&dt=12345` — order shouldn't matter.
        let json = makeResponseJSON(targetAddress: "rXyz?memo=foo&dt=12345", topLevelTag: nil, metaTag: nil)
        let response = try decodeResponse(json: json)
        XCTAssertEqual(response.resolvedDestinationTag, 12345)
        XCTAssertEqual(response.resolvedTargetAddress, "rXyz")
    }

    func testRippleResolvedTagAbsentWhenQueryHasNoDtParam() throws {
        let json = makeResponseJSON(targetAddress: "rXyz?memo=foo", topLevelTag: nil, metaTag: nil)
        let response = try decodeResponse(json: json)
        XCTAssertNil(response.resolvedDestinationTag)
        // Bare r-address still extracted, query suffix stripped.
        XCTAssertEqual(response.resolvedTargetAddress, "rXyz")
    }

    func testRippleResolvedTagFromPipeSuffix() throws {
        let json = makeResponseJSON(targetAddress: "rXyz|67890", topLevelTag: nil, metaTag: nil)
        let response = try decodeResponse(json: json)
        XCTAssertEqual(response.resolvedDestinationTag, 67890)
        XCTAssertEqual(response.resolvedTargetAddress, "rXyz")
    }

    // MARK: - Destination tag — Case C (separate field)

    func testRippleResolvedTagFromTopLevelField() throws {
        let json = makeResponseJSON(targetAddress: "rXyz", topLevelTag: 11111, metaTag: nil)
        let response = try decodeResponse(json: json)
        XCTAssertEqual(response.resolvedDestinationTag, 11111)
        XCTAssertEqual(response.resolvedTargetAddress, "rXyz")
    }

    func testRippleResolvedTagFromMetaField() throws {
        let json = makeResponseJSON(targetAddress: "rXyz", topLevelTag: nil, metaTag: 22222)
        let response = try decodeResponse(json: json)
        XCTAssertEqual(response.resolvedDestinationTag, 22222)
    }

    // MARK: - Precedence: top-level > meta > suffix

    func testRippleTopLevelTagBeatsMetaTag() throws {
        let json = makeResponseJSON(targetAddress: "rXyz", topLevelTag: 100, metaTag: 200)
        let response = try decodeResponse(json: json)
        XCTAssertEqual(response.resolvedDestinationTag, 100, "Top-level field wins over meta")
    }

    func testRippleMetaTagBeatsSuffix() throws {
        let json = makeResponseJSON(targetAddress: "rXyz?dt=300", topLevelTag: nil, metaTag: 200)
        let response = try decodeResponse(json: json)
        XCTAssertEqual(response.resolvedDestinationTag, 200, "Meta field wins over targetAddress suffix")
    }

    func testRippleTopLevelTagBeatsSuffix() throws {
        let json = makeResponseJSON(targetAddress: "rXyz?dt=300", topLevelTag: 100, metaTag: nil)
        let response = try decodeResponse(json: json)
        XCTAssertEqual(response.resolvedDestinationTag, 100, "Top-level wins over suffix")
    }

    // MARK: - Decoder accepts both txType aliases

    func testRippleDecoderAcceptsCanonicalXrpTxType() throws {
        let json = makeResponseJSON(targetAddress: "rXyz", topLevelTag: nil, metaTag: nil, txType: "XRP")
        let response = try decodeResponse(json: json)
        guard case .rippleDepositOnly = response.tx else {
            return XCTFail("expected .rippleDepositOnly for txType=XRP")
        }
    }

    func testRippleDecoderAcceptsDefensiveRippleTxType() throws {
        let json = makeResponseJSON(targetAddress: "rXyz", topLevelTag: nil, metaTag: nil, txType: "RIPPLE")
        let response = try decodeResponse(json: json)
        guard case .rippleDepositOnly = response.tx else {
            return XCTFail("expected .rippleDepositOnly for txType=RIPPLE")
        }
    }

    // MARK: - Payload builder

    func testRipplePayloadBuilderSetsXRPTxTypeAndEmptyPayload() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-xrp-swap"
        )
        let from = makeXrpCoin()
        let to = makeUsdcCoin()
        let payload = SwapCryptoLogic.buildSwapKitRipplePayload(
            fromCoin: from,
            toCoin: to,
            fromAmountInCoin: BigInt(250_000_000), // 250 XRP × 1e6 drops
            toAmountDecimal: Decimal(string: "339.418818") ?? 0,
            resolvedTargetAddress: response.resolvedTargetAddress,
            destinationTag: response.resolvedDestinationTag.map { String($0) },
            swapResponse: response
        )
        XCTAssertEqual(payload.txType, "XRP")
        XCTAssertEqual(payload.txPayload, Data(), "Deposit-only — no transaction body to ship")
        XCTAssertEqual(payload.targetAddress, response.targetAddress)
        XCTAssertEqual(payload.subProvider, "NEAR")
        XCTAssertNil(payload.memo, "No tag in this fixture — memo stays nil")
    }

    func testRipplePayloadBuilderStringifiesDestinationTagIntoMemo() throws {
        // Synthesize a response with a destination tag to exercise the memo
        // plumbing through buildSwapKitRipplePayload.
        let response = try synthesizeResponse(topLevelTag: 54321)
        let from = makeXrpCoin()
        let to = makeUsdcCoin()
        let payload = SwapCryptoLogic.buildSwapKitRipplePayload(
            fromCoin: from,
            toCoin: to,
            fromAmountInCoin: BigInt(250_000_000),
            toAmountDecimal: 0,
            resolvedTargetAddress: response.resolvedTargetAddress,
            destinationTag: response.resolvedDestinationTag.map { String($0) },
            swapResponse: response
        )
        XCTAssertEqual(payload.memo, "54321")
    }

    // MARK: - EVM builder defence-in-depth

    func testEvmBuilderRejectsRippleDepositOnly() throws {
        let response = try synthesizeResponse(topLevelTag: nil)
        XCTAssertThrowsError(try SwapCryptoLogic.buildEVMQuoteFromSwapKit(swapResponse: response)) { err in
            guard case SwapKitError.unsupportedTxType(let txType) = err else {
                return XCTFail("expected unsupportedTxType, got \(err)")
            }
            XCTAssertEqual(txType, "XRP")
        }
    }

    // MARK: - Helpers

    private func makeXrpCoin() -> Coin {
        let meta = CoinMeta.make(chain: .ripple, ticker: "XRP", decimals: 6, isNativeToken: true)
        return Coin(asset: meta, address: "rPVMhWBsfF9iMXYj3aAzJVkPDTFNSyWdKy", hexPublicKey: "")
    }

    private func makeUsdcCoin() -> Coin {
        let meta = CoinMeta.make(chain: .ethereum, ticker: "USDC", decimals: 6, isNativeToken: false)
        return Coin(asset: meta, address: "0xtest", hexPublicKey: "")
    }

    private func decodeResponse(json: String) throws -> SwapKitSwapResponse {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try JSONDecoder().decode(SwapKitSwapResponse.self, from: data)
    }

    private func synthesizeResponse(topLevelTag: UInt64?) throws -> SwapKitSwapResponse {
        try decodeResponse(json: makeResponseJSON(
            targetAddress: "rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh",
            topLevelTag: topLevelTag,
            metaTag: nil
        ))
    }

    private func makeResponseJSON(
        targetAddress: String,
        topLevelTag: UInt64?,
        metaTag: UInt64?,
        txType: String = "XRP"
    ) -> String {
        let topLevel = topLevelTag.map { ",\"destinationTag\":\($0)" } ?? ""
        let metaTagField = metaTag.map { ",\"destinationTag\":\($0)" } ?? ""
        return """
        {
            "swapId":"abc",
            "routeId":"def",
            "providers":["NEAR"],
            "sellAsset":"XRP.XRP",
            "buyAsset":"ETH.USDC",
            "sellAmount":"250",
            "expectedBuyAmount":"100",
            "expectedBuyAmountMaxSlippage":"99",
            "sourceAddress":"rSource",
            "destinationAddress":"0x0",
            "targetAddress":"\(targetAddress)",
            "meta":{"txType":"\(txType)"\(metaTagField)},
            "fees":[]
            \(topLevel)
        }
        """
    }
}
