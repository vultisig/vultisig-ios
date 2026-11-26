//
//  BondRewardHistoryWalkerTests.swift
//  VultisigAppTests
//
//  Retries, the fetch window, saved rows, and where the walk stops.
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
        var total: Int {
            lock.lock()
            defer { lock.unlock() }
            return counts.values.reduce(0, +)
        }
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func churn(_ height: Int, daysAgo: Double) -> ChurnEntry {
        let date = now.addingTimeInterval(-daysAgo * 24 * 60 * 60)
        return ChurnEntry(date: String(Int64(date.timeIntervalSince1970 * 1_000_000_000)), height: String(height))
    }

    private func saved(_ height: Int) -> BondRewardHistoryEntry {
        BondRewardHistoryEntry(churnHeight: height, churnDate: Date(timeIntervalSince1970: 0), amount: 7)
    }

    private var recentChurns: [ChurnEntry] {
        [churn(300, daysAgo: 1), churn(200, daysAgo: 2), churn(100, daysAgo: 3)]
    }

    private func walk(
        _ churns: [ChurnEntry],
        limit: Int = .max,
        known: [Int: BondRewardHistoryEntry] = [:],
        unbonds: [Int] = [],
        query: @escaping @Sendable (Int) -> BondRewardHistoryQueryResult
    ) async throws -> [BondRewardHistoryEntry] {
        try await BondRewardHistoryWalker.walk(
            churns: churns,
            limit: limit,
            known: known,
            now: now,
            unbondHeights: { _, _ in unbonds },
            query: { height, _ in query(height) }
        )
    }

    func testAQueryThatFailsOnceIsRetried() async throws {
        let calls = Calls()

        let history = try await walk(recentChurns) { height in
            calls.record(height) == 1 ? .failed(Unreachable()) : found(height)
        }

        XCTAssertEqual(history.map(\.id), [300, 200, 100])
    }

    func testAQueryThatKeepsFailingIsTriedTwiceThenEndsTheWalk() async throws {
        let calls = Calls()

        let history = try await walk(recentChurns) { height in
            _ = calls.record(height)
            return height == 199 ? .failed(Unreachable()) : found(height)
        }

        XCTAssertEqual(calls.count(199), 2)
        XCTAssertEqual(history.map(\.id), [300])
    }

    func testTheWalkEndsAtTheFirstFailedChurnEvenWhenAnOlderOneInTheBatchPaid() async throws {
        let history = try await walk(recentChurns) { height in
            height == 199 ? .failed(Unreachable()) : found(height)
        }

        XCTAssertEqual(history.map(\.id), [300])
    }

    func testOnlyChurnsInsideTheFetchWindowAreQueried() async throws {
        let calls = Calls()
        let churns = [churn(300, daysAgo: 1), churn(200, daysAgo: 12), churn(100, daysAgo: 14)]

        let history = try await walk(churns) { height in
            _ = calls.record(height)
            return found(height)
        }

        XCTAssertEqual(history.map(\.id), [300, 200])
        XCTAssertEqual(calls.count(99), 0)
    }

    func testSavedRowsOlderThanTheFetchWindowAreStillShown() async throws {
        let calls = Calls()
        let churns = [churn(300, daysAgo: 1), churn(200, daysAgo: 20), churn(100, daysAgo: 40)]

        let history = try await walk(churns, known: [200: saved(200), 100: saved(100)]) { height in
            _ = calls.record(height)
            return found(height)
        }

        XCTAssertEqual(history.map(\.id), [300, 200, 100])
        XCTAssertEqual(history.map(\.amount), [1, 7, 7])
        XCTAssertEqual(calls.total, 1)
    }

    func testSavedRowsPastAChurnTheAddressDidNotProvideForAreNotShown() async throws {
        let churns = [churn(300, daysAgo: 1), churn(200, daysAgo: 2), churn(100, daysAgo: 40)]

        let history = try await walk(churns, known: [100: saved(100)]) { height in
            height == 199 ? .notAProvider : found(height)
        }

        XCTAssertEqual(history.map(\.id), [300])
    }

    func testSavedRowsPastAGapAreNotShownWhenTheBondWasUnbondedInIt() async throws {
        let churns = [churn(300, daysAgo: 1), churn(200, daysAgo: 20), churn(100, daysAgo: 40)]

        let history = try await walk(churns, known: [100: saved(100)], unbonds: [150]) { found($0) }

        XCTAssertEqual(history.map(\.id), [300])
    }

    func testANewestChurnOutsideTheWindowIsServedOnlyFromTheSavedRow() async throws {
        let calls = Calls()
        let churns = [churn(300, daysAgo: 20), churn(200, daysAgo: 23)]
        let query: @Sendable (Int) -> BondRewardHistoryQueryResult = { height in
            _ = calls.record(height)
            return found(height)
        }

        let fromSaved = try await walk(churns, limit: 1, known: [300: saved(300)], query: query)
        let unsaved = try await walk(churns, limit: 1, query: query)

        XCTAssertEqual(fromSaved.map(\.amount), [7])
        XCTAssertTrue(unsaved.isEmpty)
        XCTAssertEqual(calls.total, 0)
    }

    func testAnUnreadableNewestChurnIsNotReplacedByAnOlderSavedRow() async throws {
        let churns = [ChurnEntry(date: "not-a-date", height: "300"), churn(200, daysAgo: 20)]

        let lastReward = try await walk(churns, limit: 1, known: [200: saved(200)]) { found($0) }

        XCTAssertTrue(lastReward.isEmpty)
    }
}
