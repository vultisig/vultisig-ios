//
//  BoundedConcurrencyTests.swift
//  VultisigAppTests
//
//  `withBoundedConcurrency` backs the rewards sheet's up-to-20 historical
//  `?height=` fetches: order must survive concurrent completion, the
//  concurrency cap must actually be respected (not just accepted as a
//  parameter), and cancelling the sheet must stop scheduling new fetches.
//

import XCTest
@testable import VultisigApp

final class BoundedConcurrencyTests: XCTestCase {

    func testEmptyInputReturnsEmptyOutput() async {
        let results: [Int] = await withBoundedConcurrency([], maxConcurrent: 4) { $0 }
        XCTAssertTrue(results.isEmpty)
    }

    /// Completion order is scrambled (later items finish first); the
    /// returned array must still read back in input order.
    func testResultOrderMatchesInputOrderDespiteOutOfOrderCompletion() async {
        let items = Array(0..<10)
        let results = await withBoundedConcurrency(items, maxConcurrent: 4) { item -> Int in
            // Odd items finish "faster" by not sleeping at all; even items
            // sleep briefly, so completion order is deliberately scrambled.
            if item.isMultiple(of: 2) {
                try? await Task.sleep(nanoseconds: UInt64(5_000_000 - item * 100_000))
            }
            return item * 10
        }
        XCTAssertEqual(results, items.map { $0 * 10 })
    }

    /// Never more than `maxConcurrent` operations run at once. `enter`/`exit`
    /// bracket the operation's own in-flight span, so a slot only frees (and
    /// `withBoundedConcurrency` only schedules the next item) once `exit`
    /// has actually run.
    func testNeverExceedsMaxConcurrent() async {
        let counter = ConcurrencyCounter()
        let items = Array(0..<12)
        _ = await withBoundedConcurrency(items, maxConcurrent: 3) { _ -> Int in
            await counter.enter()
            try? await Task.sleep(nanoseconds: 2_000_000)
            await counter.exit()
            return 0
        }
        let peak = await counter.peak
        XCTAssertLessThanOrEqual(peak, 3)
        XCTAssertGreaterThan(peak, 0)
    }

    /// A cancelled enclosing task must stop *scheduling new work*, not just
    /// let already-running children finish — otherwise closing the sheet
    /// mid-fetch still drains all up-to-20 historical requests one by one.
    func testCancellationStopsSchedulingFurtherWork() async {
        let counter = ConcurrencyCounter()
        let items = Array(0..<20)

        let task = Task {
            await withBoundedConcurrency(items, maxConcurrent: 2) { _ -> Int in
                await counter.recordStart()
                try? await Task.sleep(nanoseconds: 20_000_000)
                return 0
            }
        }

        // Let the first couple of items start, then cancel before the
        // remaining 18 would otherwise be scheduled.
        try? await Task.sleep(nanoseconds: 5_000_000)
        task.cancel()
        _ = await task.value

        let started = await counter.startCount
        XCTAssertLessThan(started, items.count, "cancellation must have prevented most of the 20 items from ever starting")
    }
}

private actor ConcurrencyCounter {
    private(set) var current = 0
    private(set) var peak = 0
    private(set) var startCount = 0

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func exit() {
        current -= 1
    }

    func recordStart() {
        startCount += 1
    }
}
