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
        // Multi-byte odd-length must also reject — earlier impl partial-decoded
        // and produced "A" for "414".
        XCTAssertEqual("414".hexToAscii(), "")
    }

    func testHexToAsciiNonHexReturnsEmpty() {
        XCTAssertEqual("zz".hexToAscii(), "")
    }

    func testHexToAsciiEmptyReturnsEmpty() {
        XCTAssertEqual("".hexToAscii(), "")
    }

    func testHexToAsciiMasksHighBitAndStripsControl() {
        // 0xC3 is masked to 0x43 ('C') and survives the printable filter.
        XCTAssertEqual("c3".hexToAscii(), "C")
        // 0x1F is a control char (US) — stripped.
        XCTAssertEqual("1f".hexToAscii(), "")
        // 0x7F (DEL) is stripped.
        XCTAssertEqual("7f".hexToAscii(), "")
    }

    func testHexToAsciiHandlesCip68Prefixes() {
        // CIP-68 fungible token label (333) = 0x0014df10, followed by "USDM".
        // The leading [NUL, DC4, 0xdf→0x5f='_', DLE] resolves to "_" after
        // the printable-only filter; full result is "_USDM".
        XCTAssertEqual("0014df105553444d".hexToAscii(), "_USDM")
    }

    func testHexToAsciiReturnsEmptyWhenAllBytesAreControl() {
        // All bytes resolve to control characters → empty so callers fall
        // back to the policy-id prefix.
        XCTAssertEqual("00010203".hexToAscii(), "")
    }
}
