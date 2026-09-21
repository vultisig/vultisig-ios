//
//  SheetPresentedCounterManagerTests.swift
//  VultisigAppTests
//

import Combine
import XCTest
@testable import VultisigApp

final class SheetPresentedCounterManagerTests: XCTestCase {
    func testDimOnlySheetsAreCountedApartFromBlurringOnes() {
        let manager = SheetPresentedCounterManager()

        manager.increment(for: .dimOnly)
        manager.increment(for: .blurred)
        manager.increment(for: .dimOnly)

        XCTAssertEqual(manager.count(for: .dimOnly), 2)
        XCTAssertEqual(manager.count(for: .blurred), 1)
        XCTAssertEqual(manager.counter, 1)
    }

    func testDecrementNeverGoesBelowZero() {
        let manager = SheetPresentedCounterManager()

        manager.decrement(for: .dimOnly)

        XCTAssertEqual(manager.dimOnlyCounter, 0)
    }

    func testResettingOneCountLeavesTheOther() {
        let manager = SheetPresentedCounterManager()
        manager.increment(for: .dimOnly)
        manager.increment(for: .blurred)

        manager.resetCounter(for: .blurred)

        XCTAssertEqual(manager.counter, 0)
        XCTAssertEqual(manager.dimOnlyCounter, 1)

        manager.increment(for: .blurred)
        manager.resetCounter(for: .dimOnly)

        XCTAssertEqual(manager.counter, 1)
        XCTAssertEqual(manager.dimOnlyCounter, 0)
    }

    func testResetAllCountersClearsBoth() {
        let manager = SheetPresentedCounterManager()
        manager.increment(for: .dimOnly)
        manager.increment(for: .blurred)

        manager.resetAllCounters()

        XCTAssertEqual(manager.counter, 0)
        XCTAssertEqual(manager.dimOnlyCounter, 0)
    }

    func testResettingAZeroCountDoesNotPublish() {
        let manager = SheetPresentedCounterManager()
        var updates = 0
        let subscription = manager.objectWillChange.sink { updates += 1 }
        defer { subscription.cancel() }

        manager.resetAllCounters()
        manager.resetCounter(for: .dimOnly)
        manager.decrement(for: .dimOnly)

        XCTAssertEqual(updates, 0)
    }
}
