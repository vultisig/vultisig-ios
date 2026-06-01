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
}
