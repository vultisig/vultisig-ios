//
//  QBTCChainServiceTests.swift
//  VultisigAppTests
//
//  Pure-helper tests for QBTCChainService (no network).
//  Mirrors vultisig-sdk/.../getClaimWithProofDisabled.ts.
//
//  Post-qbtc#158 the iOS-side cosmos auth/account/broadcast paths are
//  gone (the proof service signs + broadcasts directly), so this file
//  only covers what remains: the kill-switch param parse + the
//  `QBTCParamResponse` DTO shape.
//

@testable import VultisigApp
import XCTest

final class QBTCChainServiceTests: XCTestCase {
    // MARK: - parseDisabledFlag

    func testDisabledFlagZeroIsEnabled() throws {
        XCTAssertFalse(try QBTCChainService.parseDisabledFlag("0"))
    }

    func testDisabledFlagOneIsDisabled() throws {
        XCTAssertTrue(try QBTCChainService.parseDisabledFlag("1"))
    }

    func testDisabledFlagAnyPositiveIsDisabled() throws {
        XCTAssertTrue(try QBTCChainService.parseDisabledFlag("5"))
        XCTAssertTrue(try QBTCChainService.parseDisabledFlag("9999"))
    }

    func testDisabledFlagRejectsNonNumeric() {
        XCTAssertThrowsError(try QBTCChainService.parseDisabledFlag("yes"))
        XCTAssertThrowsError(try QBTCChainService.parseDisabledFlag(""))
        XCTAssertThrowsError(try QBTCChainService.parseDisabledFlag("1.5"))
    }

    // MARK: - DTO decoding

    func testParamResponseDecodes() throws {
        let json = #"{"param":{"key":"ClaimWithProofDisabled","value":"0"}}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(QBTCParamResponse.self, from: json)
        XCTAssertEqual(decoded.param.key, "ClaimWithProofDisabled")
        XCTAssertEqual(decoded.param.value, "0")
    }
}
