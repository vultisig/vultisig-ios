//
//  TierGatedTapTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import SwiftUI
import XCTest

@MainActor
final class TierGatedTapTests: XCTestCase {

    func test_unlocked_runsOnUnlocked_andLeavesSheetNil() async {
        var presented: VultDiscountTier?
        let binding = Binding<VultDiscountTier?>(
            get: { presented },
            set: { presented = $0 }
        )
        var didRun = false

        await TierGatedTap.handle(
            required: .silver,
            show: binding,
            for: .example,
            isUnlocked: { _, _ in true },
            onUnlocked: { didRun = true }
        )

        XCTAssertTrue(didRun)
        XCTAssertNil(presented)
    }

    func test_locked_setsSheetToRequiredTier_andSkipsOnUnlocked() async {
        var presented: VultDiscountTier?
        let binding = Binding<VultDiscountTier?>(
            get: { presented },
            set: { presented = $0 }
        )
        var didRun = false

        await TierGatedTap.handle(
            required: .silver,
            show: binding,
            for: .example,
            isUnlocked: { _, _ in false },
            onUnlocked: { didRun = true }
        )

        XCTAssertFalse(didRun)
        XCTAssertEqual(presented, .silver)
    }
}
