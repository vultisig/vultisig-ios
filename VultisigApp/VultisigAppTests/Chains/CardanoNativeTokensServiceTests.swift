//
//  CardanoNativeTokensServiceTests.swift
//  VultisigApp
//

@testable import VultisigApp
import XCTest

final class CardanoNativeTokensServiceTests: XCTestCase {

    private let policy = String(repeating: "a", count: 56)

    // MARK: - Ticker derivation (matches SDK findCardanoCoins)

    func testTickerDecodesAsciiAssetName() {
        // "GES" in hex
        let entry = CardanoAssetEntry(policyId: policy.uppercased(), assetName: "474553", fingerprint: nil, decimals: 6, quantity: "1")
        let m = CardanoNativeTokensService.makeMetadata(from: entry)
        XCTAssertEqual(m.ticker, "GES")
        XCTAssertEqual(m.policyId, policy)
        XCTAssertEqual(m.assetNameHex, "474553")
        XCTAssertEqual(m.assetId, "\(policy).474553")
        XCTAssertEqual(m.decimals, 6)
    }

    func testTickerFallsBackToPolicyPrefixWhenAssetNameEmpty() {
        let entry = CardanoAssetEntry(policyId: policy, assetName: "", fingerprint: nil, decimals: 0, quantity: "1")
        let m = CardanoNativeTokensService.makeMetadata(from: entry)
        XCTAssertEqual(m.ticker, String(policy.prefix(8)).uppercased())
    }

    func testTickerFallsBackToPolicyPrefixWhenAssetNameNil() {
        let entry = CardanoAssetEntry(policyId: policy, assetName: nil, fingerprint: nil, decimals: 0, quantity: "1")
        let m = CardanoNativeTokensService.makeMetadata(from: entry)
        XCTAssertEqual(m.ticker, String(policy.prefix(8)).uppercased())
    }

    func testNullDecimalsDefaultsToZero() {
        let entry = CardanoAssetEntry(policyId: policy, assetName: "474553", fingerprint: nil, decimals: nil, quantity: "1")
        let m = CardanoNativeTokensService.makeMetadata(from: entry)
        XCTAssertEqual(m.decimals, 0)
    }

    func testPolicyIdAndAssetNameLowercased() {
        let entry = CardanoAssetEntry(policyId: policy.uppercased(), assetName: "DEAD", fingerprint: nil, decimals: 0, quantity: "1")
        let m = CardanoNativeTokensService.makeMetadata(from: entry)
        XCTAssertEqual(m.policyId, policy)
        XCTAssertEqual(m.assetNameHex, "dead")
    }

    // MARK: - String.hexToAscii() extension

    func testHexToAsciiDecodesPrintable() {
        XCTAssertEqual("474553".hexToAscii(), "GES")
        XCTAssertEqual("48656c6c6f".hexToAscii(), "Hello")
    }

    func testHexToAsciiOddLengthReturnsEmpty() {
        XCTAssertEqual("4".hexToAscii(), "")
    }

    func testHexToAsciiNonHexReturnsEmpty() {
        XCTAssertEqual("zz".hexToAscii(), "")
    }

    func testHexToAsciiEmptyReturnsEmpty() {
        XCTAssertEqual("".hexToAscii(), "")
    }

    func testHexToAsciiHighBitMaskedToSeven() {
        // SDK uses Buffer.toString('ascii') which masks each byte to 7 bits.
        // 0xC3 (11000011) & 0x7F -> 0x43 ('C').
        XCTAssertEqual("c3".hexToAscii(), "C")
    }
}
