//
//  SwapKitLongTailTests.swift
//  VultisigAppTests
//
//  Fixture-driven decoder + payload-builder asserts for the Phase 3 source
//  chains: TON, Cardano, Sui, TRON. Each chain returns a distinct `tx` shape
//  from `/v3/swap` (`meta.txType` is the discriminator):
//
//    - TON     → `[{address, amount}]` array
//    - CARDANO → `tx: null` (deposit-only flow)
//    - SUI     → base64-encoded pre-built programmable transaction block (PTB)
//    - TRON    → TronWeb-shaped nested object with `raw_data_hex`
//
//  The keysign-side dispatcher serializes each into `SwapKitSwapPayload`
//  bytes for cross-device transit. Signing wire-up is intentionally NOT
//  validated here — it ships in the consolidated signing PR.
//

import XCTest
@testable import VultisigApp

final class SwapKitLongTailTests: XCTestCase {

    // MARK: - TON

    func testTonSwapResponseDecodesAsTonArray() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-ton-swap"
        )
        XCTAssertEqual(response.meta.txType, "TON")
        XCTAssertEqual(response.providers, ["NEAR"])
        guard case .ton(let transfers) = response.tx else {
            return XCTFail("expected .ton case, got \(response.tx)")
        }
        XCTAssertEqual(transfers.count, 1, "SwapKit returns single-element transfer array for TON")
        XCTAssertFalse(transfers[0].address.isEmpty)
        XCTAssertFalse(transfers[0].amount.isEmpty)
        XCTAssertEqual(transfers[0].address, response.targetAddress,
                       "deposit address inside `tx` must match top-level targetAddress")
    }

    func testTonQuoteFixtureSurvivesClientFilter() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitQuoteResponse.self,
            from: "v3-real-ton-quote"
        )
        let filtered = SwapKitService.filterRoutes(response.routes)
        XCTAssertEqual(filtered.count, response.routes.count,
                       "no THORChain/Maya routes in the TON fixture; nothing should be filtered")
        XCTAssertTrue(filtered.contains(where: { $0.providers == ["NEAR"] }))
    }

    // MARK: - Cardano

    func testCardanoSwapResponseDecodesAsDepositOnly() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-ada-swap"
        )
        XCTAssertEqual(response.meta.txType, "CARDANO")
        XCTAssertEqual(response.providers, ["NEAR"])
        guard case .cardano = response.tx else {
            return XCTFail("expected .cardano case (deposit-only flow), got \(response.tx)")
        }
        XCTAssertFalse(response.targetAddress.isEmpty,
                       "Cardano routing info lives entirely in targetAddress when tx is null")
        XCTAssertEqual(response.inboundAddress, response.targetAddress,
                       "deposit-only flow: inboundAddress == targetAddress")
    }

    func testCardanoCborTxTypeAliasDecodesAsDepositOnly() throws {
        // SwapKit upstream switched live from `meta.txType: "CARDANO"` to
        // `"CBOR"` without versioning. Our decoder accepts both — pin both
        // so a future flip back doesn't regress us either way.
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-ada-cbor-swap"
        )
        XCTAssertEqual(response.meta.txType, "CBOR")
        guard case .cardano = response.tx else {
            return XCTFail("`CBOR` txType must alias to .cardano (deposit-only flow), got \(response.tx)")
        }
        XCTAssertFalse(response.targetAddress.isEmpty)
    }

    // MARK: - Sui

    func testSuiSwapResponseDecodesAsPtbBase64() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-sui-swap-fresh"
        )
        XCTAssertEqual(response.meta.txType, "SUI")
        XCTAssertEqual(response.providers, ["NEAR"])
        guard case .sui(let base64) = response.tx else {
            return XCTFail("expected .sui case, got \(response.tx)")
        }
        XCTAssertGreaterThan(base64.count, 1000,
                             "Sui PTB is a multi-KB base64 string; observed fixtures are ~5KB")
        XCTAssertNotNil(Data(base64Encoded: base64),
                        "Sui PTB string must round-trip through base64 decode")
    }

    // MARK: - TRON

    func testTronSwapResponseDecodesAsTronWebObject() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-tron-final-swap-fresh"
        )
        XCTAssertEqual(response.meta.txType, "TRON")
        XCTAssertEqual(response.providers, ["NEAR"])
        guard case .tron(let tron) = response.tx else {
            return XCTFail("expected .tron case, got \(response.tx)")
        }
        XCTAssertFalse(tron.txID.isEmpty)
        XCTAssertFalse(tron.rawDataHex.isEmpty,
                       "raw_data_hex is the load-bearing field for WalletCore Tron signing")
        XCTAssertTrue(tron.rawDataHex.allSatisfy { $0.isHexDigit },
                      "raw_data_hex must be valid hex")
    }

    // MARK: - Service ranking + filter across long-tail chains

    func testLongTailFixturesAllRoutedViaNear() throws {
        // Sanity: every long-tail source chain routes via NEAR Intents in the
        // captured fixtures. The verify screen's sub-provider tag will read
        // "via NEAR" until SwapKit lights up additional providers for these
        // chains. Locks the assumption so a future provider change shows up
        // here rather than silently in production.
        for fixture in ["v3-real-ton-swap",
                        "v3-real-ada-swap",
                        "v3-sui-swap-fresh",
                        "v3-tron-final-swap-fresh"] {
            let response = try SwapKitFixtureLoader.decode(
                SwapKitSwapResponse.self,
                from: fixture
            )
            XCTAssertEqual(response.subProvider, "NEAR",
                           "fixture \(fixture) should route via NEAR")
        }
    }
}

private extension Character {
    var isHexDigit: Bool {
        ("0"..."9").contains(self) || ("a"..."f").contains(self) || ("A"..."F").contains(self)
    }
}
