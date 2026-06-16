//
//  LockedFeatureSheetViewModelTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

@MainActor
final class LockedFeatureSheetViewModelTests: XCTestCase {

    func test_customRPC_requiresSilverTier() {
        let feature = LockedFeature.customRPC
        XCTAssertEqual(feature.requiredTier, .silver)
    }

    func test_threshold_comesFromTierConfig_notMock() {
        // The Figma mock labels the Custom RPC sheet Gold / 7,500 VULT — the
        // sheet must source the threshold from the tier system instead. Custom
        // RPC stays Silver / 3,000.
        let viewModel = LockedFeatureSheetViewModel(feature: .customRPC)
        XCTAssertEqual(viewModel.requiredTier, .silver)
        XCTAssertEqual(viewModel.threshold, VultDiscountTier.silver.balanceToUnlock)
        XCTAssertEqual(viewModel.threshold, 3_000)
        XCTAssertNotEqual(viewModel.threshold, 7_500)
    }

    func test_isBelow_trueWhenBalanceUnderThreshold() {
        XCTAssertTrue(
            LockedFeatureSheetViewModel.isBelow(balance: 2_340, threshold: 3_000)
        )
    }

    func test_isBelow_falseWhenBalanceAtThreshold() {
        XCTAssertFalse(
            LockedFeatureSheetViewModel.isBelow(balance: 3_000, threshold: 3_000)
        )
    }

    func test_isBelow_falseWhenBalanceAboveThreshold() {
        XCTAssertFalse(
            LockedFeatureSheetViewModel.isBelow(balance: 5_000, threshold: 3_000)
        )
    }

    func test_isBelowThreshold_defaultsTrueWithZeroBalance() {
        let viewModel = LockedFeatureSheetViewModel(feature: .customRPC)
        XCTAssertTrue(viewModel.isBelowThreshold)
    }
}
