//
//  BondRewardHistoryWalkerTests.swift
//  VultisigAppTests
//
//  A failed node query is tried once more before the history is marked incomplete.
//

import XCTest
@testable import VultisigApp

private func found(_ height: Int) -> BondRewardHistoryQueryResult {
    .found(BondRewardHistoryEntry(churnHeight: height + 1, churnDate: Date(timeIntervalSince1970: 0), amount: 1))
}

final class BondRewardHistoryWalkerTests: XCTestCase {

    private struct Unreachable: Error {}

    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [Int: Int] = [:]
        func record(_ height: Int) -> Int {
            lock.lock()
            defer { lock.unlock() }
            counts[height, default: 0] += 1
            return counts[height] ?? 0
        }
        func count(_ height: Int) -> Int {
            lock.lock()
            defer { lock.unlock() }
            return counts[height] ?? 0
        }
    }

    private let churns = [
        ChurnEntry(date: "3000000000", height: "300"),
        ChurnEntry(date: "2000000000", height: "200"),
        ChurnEntry(date: "1000000000", height: "100")
    ]

    func testAQueryThatFailsOnceIsRetriedAndTheHistoryStaysComplete() async throws {
        let calls = Calls()

        let history = try await BondRewardHistoryWalker.walk(churns: churns, limit: 20, known: [:]) { height, _ in
            calls.record(height) == 1 ? .failed(Unreachable()) : found(height)
        }

        XCTAssertEqual(history.entries.map(\.id), [300, 200, 100])
        XCTAssertTrue(history.isComplete)
    }

    func testAQueryThatKeepsFailingIsTriedTwiceThenMarksTheHistoryIncomplete() async throws {
        let calls = Calls()

        let history = try await BondRewardHistoryWalker.walk(churns: churns, limit: 20, known: [:]) { height, _ in
            _ = calls.record(height)
            return height == 199 ? .failed(Unreachable()) : found(height)
        }

        XCTAssertEqual(calls.count(199), 2)
        XCTAssertEqual(history.entries.map(\.id), [300, 100])
        XCTAssertFalse(history.isComplete)
    }
}
