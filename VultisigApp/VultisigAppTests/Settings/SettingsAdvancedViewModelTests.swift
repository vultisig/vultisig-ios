//
//  SettingsAdvancedViewModelTests.swift
//  VultisigAppTests
//
//  The reset is destructive and irreversible, so confirmation is mandatory:
//  tapping the row must only ASK, and the wipe must run exactly once and only
//  after the user confirms.
//

import XCTest
@testable import VultisigApp

@MainActor
final class SettingsAdvancedViewModelTests: XCTestCase {

    /// Tapping the row shows the confirmation and deletes NOTHING.
    func testRequestResetShowsConfirmationWithoutWiping() {
        let spy = SpyReset()
        let viewModel = SettingsAdvancedViewModel(resetService: spy)

        viewModel.requestReset()

        XCTAssertTrue(viewModel.isConfirmingReset)
        XCTAssertEqual(spy.resetCount, 0, "Asking for confirmation must not wipe anything")
    }

    /// Dismissing / cancelling the confirmation (never calling `confirmReset`)
    /// leaves both stores untouched.
    func testCancellingConfirmationWipesNothing() {
        let spy = SpyReset()
        let viewModel = SettingsAdvancedViewModel(resetService: spy)

        viewModel.requestReset()
        viewModel.isConfirmingReset = false // the .cancel button just dismisses

        XCTAssertEqual(spy.resetCount, 0)
    }

    /// Confirming performs the wipe exactly once and dismisses the dialog.
    func testConfirmResetWipesOnceAndDismisses() {
        let spy = SpyReset()
        let viewModel = SettingsAdvancedViewModel(resetService: spy)

        viewModel.requestReset()
        viewModel.confirmReset()

        XCTAssertFalse(viewModel.isConfirmingReset)
        XCTAssertEqual(spy.resetCount, 1)
    }
}

@MainActor
private final class SpyReset: TransactionHistoryResetting {
    private(set) var resetCount = 0
    func resetAll() { resetCount += 1 }
}
