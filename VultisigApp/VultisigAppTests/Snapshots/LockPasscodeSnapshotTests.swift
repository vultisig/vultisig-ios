//
//  LockPasscodeSnapshotTests.swift
//  VultisigAppTests
//

import SnapshotTesting
import SwiftUI
import XCTest

@testable import VultisigApp

@MainActor
final class LockPasscodeSnapshotTests: XCTestCase {
    func testLockScreen_iPhone16Pro() {
        let view = LockPasscodeEntryView(
            errorMessage: nil,
            isBusy: false,
            isBiometricUnlockAvailable: true,
            passcode: .constant(""),
            onComplete: { _ in },
            onBiometricUnlock: {}
        )
        .colorScheme(.dark)

        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.99999,
                perceptualPrecision: 0.99999,
                layout: .device(config: .iPhone16Pro)
            )
        )
    }
}
