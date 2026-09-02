//
//  PasscodeInputRulesTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class PasscodeInputRulesTests: XCTestCase {
    func testAppendStopsAtThePasscodeLength() {
        XCTAssertEqual(PasscodeInputRules.appending("6", to: "12345"), "123456")
        XCTAssertNil(PasscodeInputRules.appending("7", to: "123456"))
    }

    func testDeleteRemovesOnlyTheLastDigit() {
        XCTAssertEqual(PasscodeInputRules.deletingLast(from: "123"), "12")
        XCTAssertNil(PasscodeInputRules.deletingLast(from: ""))
    }

    func testPasteAcceptsOnlyAShortAsciiNumericEntry() {
        XCTAssertEqual(PasscodeInputRules.pastedEntry(from: " 123456\n"), "123456")
        XCTAssertNil(PasscodeInputRules.pastedEntry(from: "1234567"))
        XCTAssertNil(PasscodeInputRules.pastedEntry(from: "12-34"))
        XCTAssertNil(PasscodeInputRules.pastedEntry(from: "１２３４５６"))
    }

    func testNativeEntryAcceptsOnlyUpToSixAsciiDigits() {
        XCTAssertTrue(PasscodeInputRules.acceptsNativeEntry(""))
        XCTAssertTrue(PasscodeInputRules.acceptsNativeEntry("123456"))
        XCTAssertFalse(PasscodeInputRules.acceptsNativeEntry("1234567"))
        XCTAssertFalse(PasscodeInputRules.acceptsNativeEntry("12-34"))
        XCTAssertFalse(PasscodeInputRules.acceptsNativeEntry("１２３４５６"))
    }
}
