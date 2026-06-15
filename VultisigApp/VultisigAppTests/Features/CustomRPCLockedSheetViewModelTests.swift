//
//  CustomRPCLockedSheetViewModelTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

@MainActor
final class CustomRPCLockedSheetViewModelTests: XCTestCase {

    func test_threshold_comesFromTierConfig_notMock() {
        // The Figma mock labels this Gold / 7,500 VULT — the sheet must source
        // the threshold from the tier system instead. Custom RPC stays Silver.
        let viewModel = CustomRPCLockedSheetViewModel(requiredTier: .silver)
        XCTAssertEqual(viewModel.requiredTier, .silver)
        XCTAssertEqual(viewModel.threshold, VultDiscountTier.silver.balanceToUnlock)
        XCTAssertEqual(viewModel.threshold, 3_000)
        XCTAssertNotEqual(viewModel.threshold, 7_500)
    }

    func test_isBelow_trueWhenBalanceUnderThreshold() {
        XCTAssertTrue(
            CustomRPCLockedSheetViewModel.isBelow(balance: 2_340, threshold: 3_000)
        )
    }

    func test_isBelow_falseWhenBalanceAtThreshold() {
        XCTAssertFalse(
            CustomRPCLockedSheetViewModel.isBelow(balance: 3_000, threshold: 3_000)
        )
    }

    func test_isBelow_falseWhenBalanceAboveThreshold() {
        XCTAssertFalse(
            CustomRPCLockedSheetViewModel.isBelow(balance: 5_000, threshold: 3_000)
        )
    }

    func test_isBelowThreshold_defaultsTrueWithZeroBalance() {
        let viewModel = CustomRPCLockedSheetViewModel(requiredTier: .silver)
        XCTAssertTrue(viewModel.isBelowThreshold)
    }
}
