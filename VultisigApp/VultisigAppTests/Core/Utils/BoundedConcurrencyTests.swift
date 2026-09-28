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

    func testEmptyInputReturnsEmptyOutput() async throws {
        let results: [Int] = try await withBoundedConcurrency([], maxConcurrent: 4) { $0 }
        XCTAssertTrue(results.isEmpty)
    }

    /// The fail-closed contract applies at zero items too: an
    /// already-cancelled caller must not read `[]` back as "the complete
    /// (empty) answer" — it's indistinguishable from a caller that was
    /// simply never cancelled and genuinely had nothing to do.
    func testCancelledCallWithEmptyInputThrows() async {
        let task = Task<[Int], Error> {
            try await withBoundedConcurrency([], maxConcurrent: 4) { $0 }
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("an already-cancelled call must throw even with no items to process")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    /// Completion order is scrambled (later items finish first); the
    /// returned array must still read back in input order.
    func testResultOrderMatchesInputOrderDespiteOutOfOrderCompletion() async throws {
        let items = Array(0..<10)
        let results = try await withBoundedConcurrency(items, maxConcurrent: 4) { item -> Int in
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
    func testNeverExceedsMaxConcurrent() async throws {
        let counter = ConcurrencyCounter()
        let items = Array(0..<12)
        _ = try await withBoundedConcurrency(items, maxConcurrent: 3) { _ -> Int in
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
            try? await withBoundedConcurrency(items, maxConcurrent: 2) { _ -> Int in
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

    /// The contract is fail-closed: a cancelled call must THROW, never
    /// return fewer results than requested read as "the complete answer".
    /// Items 0 and 2 launch alongside the one fast item (1) — with
    /// `maxConcurrent: 3` all three start immediately — and are still
    /// slowly running when cancellation lands right after item 1's
    /// completion is observed. The old (buggy) contract broke the
    /// observation loop there, silently dropped 0 and 2 (already in flight,
    /// but never captured because the loop had already exited) and never
    /// scheduled 3, 4, 5 at all, then handed back `compactMap` = `[1]` — a
    /// hole in the MIDDLE of the sequence, indistinguishable from "these
    /// were the only churns that mattered."
    func testCancellationThrowsInsteadOfReturningAGappedArray() async {
        let items = Array(0..<6)

        let task = Task {
            try await withBoundedConcurrency(items, maxConcurrent: 3) { item -> Int in
                // Item 1 resolves fast; 0 and 2 (launched in the same initial
                // batch) and 3/4/5 (which would only launch after a slot
                // frees) are slow — generous margin against CI jitter.
                if item != 1 {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                return item
            }
        }

        // Cancel before ANY item has completed, so whichever one finishes
        // first (item 1) is observed by the loop already-cancelled.
        try? await Task.sleep(nanoseconds: 30_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("a cancelled call must throw, not return a gapped/partial array read as complete")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
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
