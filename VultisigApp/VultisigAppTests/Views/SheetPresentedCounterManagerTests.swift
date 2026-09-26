//
//  SheetPresentedCounterManagerTests.swift
//  VultisigAppTests
//

import Combine
import XCTest
@testable import VultisigApp

final class SheetPresentedCounterManagerTests: XCTestCase {
    func testNestedSheetsShareTheCounter() {
        let manager = SheetPresentedCounterManager()

        manager.increment()
        manager.increment()
        manager.increment()

        XCTAssertEqual(manager.counter, 3)
    }

    func testDecrementNeverGoesBelowZero() {
        let manager = SheetPresentedCounterManager()

        manager.decrement()

        XCTAssertEqual(manager.counter, 0)
    }

    func testDismissingNestedSheetPreservesParentCount() {
        let manager = SheetPresentedCounterManager()
        manager.increment()
        manager.increment()

        manager.decrement()

        XCTAssertEqual(manager.counter, 1)
    }

    func testResetCounterClearsAllSheets() {
        let manager = SheetPresentedCounterManager()
        manager.increment()
        manager.increment()

        manager.resetCounter()

        XCTAssertEqual(manager.counter, 0)
    }

    func testResettingAZeroCountDoesNotPublish() {
        let manager = SheetPresentedCounterManager()
        var updates = 0
        let subscription = manager.objectWillChange.sink { updates += 1 }
        defer { subscription.cancel() }

        manager.resetCounter()
        manager.decrement()

        XCTAssertEqual(updates, 0)
    }
}
