//
//  CardanoAssetIdTests.swift
//  VultisigApp
//

@testable import VultisigApp
import XCTest

final class CardanoAssetIdTests: XCTestCase {

    private let policy = String(repeating: "a", count: 56)
    private let assetHex = "474553" // "GES"

    func testMakeJoinsLowercased() {
        let id = CardanoAssetId.make(policyId: policy.uppercased(), assetName: assetHex.uppercased())
        XCTAssertEqual(id, "\(policy).\(assetHex)")
    }

    func testParseRoundTrip() throws {
        let id = CardanoAssetId.make(policyId: policy, assetName: assetHex)
        let parsed = try CardanoAssetId.parse(id)
        XCTAssertEqual(parsed.policyId, policy)
        XCTAssertEqual(parsed.assetName, assetHex)
    }

    func testParseLowercasesMixedCase() throws {
        let mixed = "\(policy.uppercased()).\(assetHex.uppercased())"
        let parsed = try CardanoAssetId.parse(mixed)
        XCTAssertEqual(parsed.policyId, policy)
        XCTAssertEqual(parsed.assetName, assetHex)
    }

    func testParseAllowsEmptyAssetName() throws {
        let parsed = try CardanoAssetId.parse("\(policy).")
        XCTAssertEqual(parsed.policyId, policy)
        XCTAssertEqual(parsed.assetName, "")
    }

    func testParseRejectsMissingSeparator() {
        XCTAssertThrowsError(try CardanoAssetId.parse(policy)) { error in
            XCTAssertEqual(error as? CardanoAssetIdError, .missingSeparator)
        }
    }

    func testParseRejectsEmptyPolicyId() {
        XCTAssertThrowsError(try CardanoAssetId.parse(".\(assetHex)")) { error in
            XCTAssertEqual(error as? CardanoAssetIdError, .emptyPolicyId)
        }
    }

    func testParseRejectsShortPolicyId() {
        let short = String(repeating: "a", count: 10)
        XCTAssertThrowsError(try CardanoAssetId.parse("\(short).\(assetHex)")) { error in
            XCTAssertEqual(error as? CardanoAssetIdError, .invalidPolicyIdLength(10))
        }
    }

    func testParseRejectsLongPolicyId() {
        let long = String(repeating: "a", count: 60)
        XCTAssertThrowsError(try CardanoAssetId.parse("\(long).\(assetHex)")) { error in
            XCTAssertEqual(error as? CardanoAssetIdError, .invalidPolicyIdLength(60))
        }
    }

    func testParseRejectsNonHexPolicyId() {
        let bad = String(repeating: "z", count: 56)
        XCTAssertThrowsError(try CardanoAssetId.parse("\(bad).\(assetHex)")) { error in
            XCTAssertEqual(error as? CardanoAssetIdError, .nonHexPolicyId)
        }
    }

    func testParseRejectsOversizeAssetName() {
        let oversize = String(repeating: "a", count: 66)
        XCTAssertThrowsError(try CardanoAssetId.parse("\(policy).\(oversize)")) { error in
            XCTAssertEqual(error as? CardanoAssetIdError, .invalidAssetNameLength(66))
        }
    }

    func testParseRejectsNonHexAssetName() {
        XCTAssertThrowsError(try CardanoAssetId.parse("\(policy).zz")) { error in
            XCTAssertEqual(error as? CardanoAssetIdError, .nonHexAssetName)
        }
    }

    func testParseAcceptsMaxAssetNameLength() throws {
        let max = String(repeating: "f", count: CardanoAssetId.maxAssetNameHexLength)
        let parsed = try CardanoAssetId.parse("\(policy).\(max)")
        XCTAssertEqual(parsed.assetName, max)
    }
}
