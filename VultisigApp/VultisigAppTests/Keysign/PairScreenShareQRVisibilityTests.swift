//
//  PairScreenShareQRVisibilityTests.swift
//  VultisigApp
//
//  Pins the fast-vault-hides-share-button rule as a testable unit rather than
//  inline view logic. `PairScreen` has no view model, so the boolean that
//  gates the "Share QR Code" toolbar button is exposed as a static function
//  and asserted directly: a present `fastVaultPassword` (fast vault, server
//  co-signs) must never show the button; a nil one (secure, N-of-M vault)
//  always must.
//

@testable import VultisigApp
import XCTest

final class PairScreenShareQRVisibilityTests: XCTestCase {

    func testShareQRButtonHiddenWhenFastVaultPasswordIsPresent() {
        XCTAssertFalse(PairScreen.showsShareQRButton(fastVaultPassword: "some-password"))
    }

    func testShareQRButtonHiddenWhenFastVaultPasswordIsEmptyString() {
        // A fast-vault flow can hand through an empty (not nil) password; the
        // button must stay hidden the same as any other non-nil value.
        XCTAssertFalse(PairScreen.showsShareQRButton(fastVaultPassword: ""))
    }

    func testShareQRButtonShownWhenFastVaultPasswordIsNil() {
        XCTAssertTrue(PairScreen.showsShareQRButton(fastVaultPassword: nil))
    }
}
