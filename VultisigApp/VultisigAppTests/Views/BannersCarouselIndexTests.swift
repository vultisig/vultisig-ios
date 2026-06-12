//
//  BannersCarouselIndexTests.swift
//  VultisigAppTests
//
//  Unit tests for `BannersCarouselIndex`, the pure index math extracted from
//  `BannersCarousel`. Covers the auto-advance wrap-around and the post-removal
//  index recalculation — the logic that drives the carousel's state writes.
//

import XCTest
@testable import VultisigApp

final class BannersCarouselIndexTests: XCTestCase {

    // MARK: - next(after:count:) — auto-advance wrap-around

    func testNextAdvancesWithinBounds() {
        XCTAssertEqual(BannersCarouselIndex.next(after: 0, count: 3), 1)
        XCTAssertEqual(BannersCarouselIndex.next(after: 1, count: 3), 2)
    }

    func testNextWrapsFromLastToFirst() {
        XCTAssertEqual(BannersCarouselIndex.next(after: 2, count: 3), 0)
    }

    func testNextIsNoOpForSingleBanner() {
        // With a single banner there is nothing to advance to: returning the
        // same index lets the caller guard the write and avoid a no-op mutation.
        XCTAssertEqual(BannersCarouselIndex.next(after: 0, count: 1), 0)
    }

    func testNextIsNoOpForEmptyCount() {
        XCTAssertEqual(BannersCarouselIndex.next(after: 0, count: 0), 0)
    }

    // MARK: - afterRemoval(removedIndex:currentIndex:countBeforeRemoval:)

    func testRemovalOfBannerBeforeCurrentShiftsIndexBack() {
        // current = 2, remove index 0 -> the active banner is now at index 1.
        XCTAssertEqual(
            BannersCarouselIndex.afterRemoval(removedIndex: 0, currentIndex: 2, countBeforeRemoval: 3),
            1
        )
    }

    func testRemovalOfBannerAfterCurrentKeepsIndex() {
        // current = 0, remove index 2 -> still on index 0.
        XCTAssertEqual(
            BannersCarouselIndex.afterRemoval(removedIndex: 2, currentIndex: 0, countBeforeRemoval: 3),
            0
        )
    }

    func testRemovalOfCurrentNonLastKeepsIndex() {
        // current = 1 (middle), remove it -> next banner slides into slot 1.
        XCTAssertEqual(
            BannersCarouselIndex.afterRemoval(removedIndex: 1, currentIndex: 1, countBeforeRemoval: 3),
            1
        )
    }

    func testRemovalOfCurrentLastStepsBack() {
        // current = 2 (last), remove it -> step back to index 1.
        XCTAssertEqual(
            BannersCarouselIndex.afterRemoval(removedIndex: 2, currentIndex: 2, countBeforeRemoval: 3),
            1
        )
    }

    func testRemovalOfOnlyBannerResetsToZero() {
        XCTAssertEqual(
            BannersCarouselIndex.afterRemoval(removedIndex: 0, currentIndex: 0, countBeforeRemoval: 1),
            0
        )
    }

    func testRemovalOfCurrentFirstWhenItIsLastRemainingStepsBackToZero() {
        // Two banners, current = 1 (last), remove it -> back to 0.
        XCTAssertEqual(
            BannersCarouselIndex.afterRemoval(removedIndex: 1, currentIndex: 1, countBeforeRemoval: 2),
            0
        )
    }
}
