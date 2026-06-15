//
//  VultDiscountTierComparableTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class VultDiscountTierComparableTests: XCTestCase {

    func test_ordering_followsDeclarationOrder() {
        XCTAssertTrue(VultDiscountTier.bronze < VultDiscountTier.silver)
        XCTAssertTrue(VultDiscountTier.silver < VultDiscountTier.gold)
        XCTAssertTrue(VultDiscountTier.gold < VultDiscountTier.platinum)
        XCTAssertTrue(VultDiscountTier.platinum < VultDiscountTier.diamond)
        XCTAssertTrue(VultDiscountTier.diamond < VultDiscountTier.ultimate)
    }

    func test_greaterThanOrEqual_atMinimum() {
        XCTAssertTrue(VultDiscountTier.silver >= .silver)
        XCTAssertTrue(VultDiscountTier.gold >= .silver)
        XCTAssertTrue(VultDiscountTier.ultimate >= .silver)
    }

    func test_belowMinimum() {
        XCTAssertFalse(VultDiscountTier.bronze >= .silver)
    }

    func test_sorted_isAscending() {
        let shuffled: [VultDiscountTier] = [.diamond, .bronze, .gold, .ultimate, .silver, .platinum]
        XCTAssertEqual(shuffled.sorted(), VultDiscountTier.allCases)
    }

    func test_discountPerkText_numericTiers_includeBps() {
        XCTAssertTrue(VultDiscountTier.bronze.discountPerkText.contains("5"))
        XCTAssertTrue(VultDiscountTier.silver.discountPerkText.contains("10"))
        XCTAssertTrue(VultDiscountTier.gold.discountPerkText.contains("20"))
        XCTAssertTrue(VultDiscountTier.platinum.discountPerkText.contains("25"))
        XCTAssertTrue(VultDiscountTier.diamond.discountPerkText.contains("35"))
    }

    func test_discountPerkText_ultimate_neverPrintsSentinel() {
        let text = VultDiscountTier.ultimate.discountPerkText
        XCTAssertFalse(text.contains("\(Int.max)"))
        XCTAssertEqual(text, "noFee".localized)
    }

    func test_canUnlock_noActiveTier_allUnlockable() {
        for tier in VultDiscountTier.allCases {
            XCTAssertTrue(
                VultDiscountTier.canUnlock(tier, active: nil),
                "\(tier) should be unlockable when no tier is active"
            )
        }
    }

    func test_canUnlock_aboveActive_isUnlockable() {
        XCTAssertTrue(VultDiscountTier.canUnlock(.platinum, active: .gold))
        XCTAssertTrue(VultDiscountTier.canUnlock(.ultimate, active: .bronze))
    }

    func test_canUnlock_activeTier_isNotUnlockable() {
        XCTAssertFalse(VultDiscountTier.canUnlock(.gold, active: .gold))
    }

    func test_canUnlock_belowActive_isNotUnlockable() {
        XCTAssertFalse(VultDiscountTier.canUnlock(.bronze, active: .gold))
        XCTAssertFalse(VultDiscountTier.canUnlock(.silver, active: .gold))
    }
}
