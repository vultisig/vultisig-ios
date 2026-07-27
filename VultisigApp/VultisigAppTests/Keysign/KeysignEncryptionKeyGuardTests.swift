//
//  KeysignEncryptionKeyGuardTests.swift
//  VultisigApp
//
//  Pins the guard that keeps a missing or empty keysign encryption key from
//  starting a ceremony unsafely. `KeysignDiscoveryViewModel.encryptionKeyHex`
//  is optional and can also be assigned an empty string from a preset session,
//  and the signing kickoff used to consume it with `!` / `?? ""`. A nil OR
//  empty key must instead route to `.FailToStart` with a real localized
//  message — never crash, and never fall through to an empty key that peers
//  cannot decrypt (which stalls the whole committee).
//

@testable import VultisigApp
import XCTest

final class KeysignEncryptionKeyGuardTests: XCTestCase {

    @MainActor
    func testStartKeysignWithNilEncryptionKeyFailsToStartInsteadOfEmptyKey() {
        assertStartKeysignFailsToStart(withKey: nil)
    }

    @MainActor
    func testStartKeysignWithEmptyEncryptionKeyFailsToStartInsteadOfEmptyKey() {
        assertStartKeysignFailsToStart(withKey: "")
    }

    @MainActor
    private func assertStartKeysignFailsToStart(
        withKey key: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let viewModel = KeysignDiscoveryViewModel()
        viewModel.encryptionKeyHex = key

        let input = viewModel.startKeysign(vault: .example)

        XCTAssertNil(
            input,
            "A missing/empty encryption key must not produce a KeysignInput carrying an unusable key",
            file: file,
            line: line
        )
        XCTAssertEqual(viewModel.status, .FailToStart, file: file, line: line)

        // The message must be the resolved localization — not an empty fallback
        // and not the raw key that `NSLocalizedString` returns when the string
        // is absent. Assert the lookup actually resolved, so this doesn't pass
        // as a tautology against the same failing lookup.
        XCTAssertEqual(viewModel.errorMessage, "missingEncryptionKey".localized, file: file, line: line)
        XCTAssertFalse(
            viewModel.errorMessage.isEmpty,
            "Localized error message must not be empty",
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            viewModel.errorMessage,
            "missingEncryptionKey",
            "errorMessage must be the localized string, not the raw key (missing localization)",
            file: file,
            line: line
        )
    }
}
