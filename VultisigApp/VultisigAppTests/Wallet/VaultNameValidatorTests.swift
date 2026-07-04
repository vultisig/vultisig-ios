//
//  VaultNameValidatorTests.swift
//  VultisigAppTests
//
//  Pins the shared vault-name validation used by vault creation and
//  Vault Settings -> Rename: empty and whitespace-only names are rejected,
//  and names already taken by another vault are rejected case-insensitively.
//

@testable import VultisigApp
import XCTest

final class VaultNameValidatorTests: XCTestCase {

    private let existingNames = ["Main Vault", "Treasury"]

    private func makeValidator() -> VaultNameValidator {
        VaultNameValidator(existingNames: existingNames)
    }

    // MARK: - Empty / whitespace

    func testEmptyNameRejected() {
        XCTAssertFalse(makeValidator().validateNonThrowable(value: ""))
    }

    func testWhitespaceOnlyNameRejected() {
        XCTAssertFalse(makeValidator().validateNonThrowable(value: "   "))
        XCTAssertFalse(makeValidator().validateNonThrowable(value: "\n\t "))
    }

    // MARK: - Valid names

    func testValidNameAccepted() {
        XCTAssertTrue(makeValidator().validateNonThrowable(value: "Savings"))
    }

    func testValidNameWithSurroundingWhitespaceAccepted() {
        XCTAssertTrue(makeValidator().validateNonThrowable(value: "  Savings  "))
    }

    func testValidNameAcceptedWhenNoExistingVaults() {
        let validator = VaultNameValidator(existingNames: [])
        XCTAssertTrue(validator.validateNonThrowable(value: "Savings"))
    }

    // MARK: - Duplicates

    func testDuplicateNameRejected() {
        XCTAssertFalse(makeValidator().validateNonThrowable(value: "Main Vault"))
    }

    func testDuplicateNameRejectedCaseInsensitively() {
        XCTAssertFalse(makeValidator().validateNonThrowable(value: "main vault"))
        XCTAssertFalse(makeValidator().validateNonThrowable(value: "TREASURY"))
    }

    func testDuplicateNameRejectedWhenSurroundedByWhitespace() {
        XCTAssertFalse(makeValidator().validateNonThrowable(value: "  Treasury "))
    }

    func testDuplicateDetectedWhenExistingNameHasWhitespacePadding() {
        let validator = VaultNameValidator(existingNames: [" Treasury "])
        XCTAssertFalse(validator.validateNonThrowable(value: "Treasury"))
    }
}
