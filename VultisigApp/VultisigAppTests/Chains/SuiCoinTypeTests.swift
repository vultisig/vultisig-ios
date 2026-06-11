//
//  SuiCoinTypeTests.swift
//  VultisigApp
//
//  Pins exact, normalization-aware SUI coin-object matching: a native SUI send
//  must never pull in look-alike coins whose type merely contains "SUI" (LSTs
//  like xSUI/haSUI, SUI-named memecoins), a token send must select objects by
//  the token's fully-qualified type even when its on-chain symbol differs from
//  the display ticker (Wormhole-bridged `…::coin::COIN`), and package-address
//  form (short `0x2` vs long `0x00…02`) must not affect equality.
//

@testable import VultisigApp
import XCTest

final class SuiCoinTypeTests: XCTestCase {

    private let nativeShort = "0x2::sui::SUI"
    private let nativeLong = "0x0000000000000000000000000000000000000000000000000000000000000002::sui::SUI"
    private let xSUI = "0xb45f7a8e2d1c4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a::xsui::XSUI"
    // Wormhole-bridged asset: on-chain symbol/struct is COIN, not the display ticker.
    private let bridgedCoin = "0x5d4b302506645c37ff133b98c4b50a5ae14841659738d6d733d59d0d217a93bf::coin::COIN"

    // MARK: - Native matching excludes look-alikes

    func testIsNativeMatchesShortAndLongAddressForms() {
        XCTAssertTrue(SuiCoinType.isNative(nativeShort))
        XCTAssertTrue(SuiCoinType.isNative(nativeLong))
    }

    func testIsNativeRejectsLookAlikeLstAndMemecoins() {
        XCTAssertFalse(SuiCoinType.isNative(xSUI))
        XCTAssertFalse(SuiCoinType.isNative(bridgedCoin))
        XCTAssertFalse(SuiCoinType.isNative("0xabc::sssui::SSSUI"))
    }

    // MARK: - Address-form normalization

    func testNormalizeCollapsesAddressForms() {
        XCTAssertEqual(SuiCoinType.normalize(nativeShort), SuiCoinType.normalize(nativeLong))
        XCTAssertTrue(SuiCoinType.matches(nativeShort, nativeLong))
    }

    func testNormalizeIsCaseInsensitive() {
        XCTAssertTrue(SuiCoinType.matches(bridgedCoin, bridgedCoin.uppercased()))
    }

    func testNormalizeLeavesNonNativeTypesDistinct() {
        XCTAssertFalse(SuiCoinType.matches(nativeShort, xSUI))
        XCTAssertFalse(SuiCoinType.matches(bridgedCoin, xSUI))
    }

    // MARK: - expectedType resolves the record's coin type

    func testExpectedTypeForNativeRecordIsCanonicalSui() {
        XCTAssertEqual(SuiCoinType.expectedType(isNativeToken: true, contractAddress: ""), nativeShort)
    }

    func testExpectedTypeForTokenRecordIsContractAddress() {
        XCTAssertEqual(
            SuiCoinType.expectedType(isNativeToken: false, contractAddress: bridgedCoin),
            bridgedCoin
        )
    }

    // MARK: - Selection over a heterogeneous object set

    /// A wallet holding native SUI alongside an xSUI LST: a native send must
    /// select only the native object and never the LST.
    func testNativeSelectionExcludesXSui() {
        let objects = [
            ["coinType": nativeLong, "objectID": "0xnative"],
            ["coinType": xSUI, "objectID": "0xlst"]
        ]
        let selected = objects.filter { SuiCoinType.isNative($0["coinType"] ?? "") }
        XCTAssertEqual(selected.map { $0["objectID"] }, ["0xnative"])
    }

    /// A token send for a Wormhole-bridged `…::coin::COIN` asset selects its own
    /// objects (by exact type) and a separate SUI gas object — never the xSUI LST.
    func testBridgedTokenSelectionAndGasSplit() {
        let objects = [
            ["coinType": nativeLong, "objectID": "0xgas"],
            ["coinType": bridgedCoin, "objectID": "0xtoken"],
            ["coinType": xSUI, "objectID": "0xlst"]
        ]
        let tokenType = SuiCoinType.expectedType(isNativeToken: false, contractAddress: bridgedCoin)

        let tokenObjects = objects.filter { SuiCoinType.matches($0["coinType"] ?? "", tokenType) }
        let gasObjects = objects.filter { SuiCoinType.isNative($0["coinType"] ?? "") }

        XCTAssertEqual(tokenObjects.map { $0["objectID"] }, ["0xtoken"])
        XCTAssertEqual(gasObjects.map { $0["objectID"] }, ["0xgas"])
    }
}
