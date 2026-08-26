//
//  TTLCacheCancellationTests.swift
//  VultisigAppTests
//
//  Pins the one behaviour of `TTLCache` that decides whether a cancelled fetch
//  can be mistaken for a failed one: cancellation must propagate, never be
//  answered from the last-good entry.
//
//  `TTLCache.value` serves stale data when a fetch throws — deliberately, so a
//  flaky node does not blank the UI — and exempts cancellation from that
//  fail-open via `if error is CancellationError { throw error }`. That exemption
//  only works while cancellation actually arrives as a bare `CancellationError`.
//  It does, but not for a local reason: `HTTPClient` converts
//  `URLError.cancelled` into `CancellationError()` before any cache sees it.
//
//  So the guarantee spans two files, and nothing in `TTLCache` would notice if
//  the conversion in `HTTPClient` changed. These tests pin the cache side; the
//  cross-file dependency is called out here so the coupling is visible to
//  whoever edits either end.
//

@testable import VultisigApp
import XCTest

final class TTLCacheCancellationTests: XCTestCase {

    private let ttl: TimeInterval = 60
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private struct FetchFailure: Error {}

    // MARK: - Cancellation is never answered from cache

    func testCancellationPropagatesWhenNothingIsCached() async {
        let cache = TTLCache<String, Int>()

        do {
            _ = try await cache.value(for: "k", now: now, ttl: ttl) { throw CancellationError() }
            XCTFail("Expected the cancellation to propagate")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    /// The case that matters. A stale entry exists, so the fail-open path is
    /// available — and cancellation must still refuse it. Serving cached data
    /// here would report success for work the caller had already abandoned.
    func testCancellationPropagatesEvenWhenAStaleEntryIsAvailable() async {
        let cache = TTLCache<String, Int>()
        await cache.setCached(7, for: "k", fetchedAt: now.addingTimeInterval(-3600))

        do {
            _ = try await cache.value(for: "k", now: now, ttl: ttl) { throw CancellationError() }
            XCTFail("Expected the cancellation to propagate rather than serve 7")
        } catch {
            XCTAssertTrue(error is CancellationError, "got \(error) — a cancelled fetch was treated as a failed one")
        }
    }

    /// The contrast that proves the distinction is real: an ordinary failure
    /// *does* fall back to the last-good entry.
    func testAnOrdinaryFailureStillServesTheStaleEntry() async throws {
        let cache = TTLCache<String, Int>()
        await cache.setCached(7, for: "k", fetchedAt: now.addingTimeInterval(-3600))

        let value = try await cache.value(for: "k", now: now, ttl: ttl) { throw FetchFailure() }

        XCTAssertEqual(value, 7)
    }

    func testAnOrdinaryFailureWithNothingCachedRethrows() async {
        let cache = TTLCache<String, Int>()

        do {
            _ = try await cache.value(for: "k", now: now, ttl: ttl) { throw FetchFailure() }
            XCTFail("Expected the failure to propagate")
        } catch {
            XCTAssertTrue(error is FetchFailure)
        }
    }

    // MARK: - Through the coalescing wrapper

    /// Concurrent callers share one in-flight `Task`, so the joiner receives the
    /// same error the creator does — the exemption cannot be bypassed by
    /// arriving second.
    ///
    /// The fetch count is asserted, and the second caller is released only once
    /// the first is known to be in flight. Without both, this test would pass
    /// just as happily against two independent fetches that each threw — which
    /// would prove nothing about coalescing.
    func testCancellationReachesACoalescedJoiner() async {
        let cache = TTLCache<String, Int>()
        await cache.setCached(7, for: "k", fetchedAt: now.addingTimeInterval(-3600))
        let gate = FetchGate()

        async let first: Int = cache.value(for: "k", now: now, ttl: ttl) {
            await Task.yield()
            await gate.markStartedAndWaitForRelease()
            throw CancellationError()
        }

        // Only proceed once the first fetch is genuinely running, so the second
        // caller must find it in `inFlight` rather than racing to create one.
        await gate.waitUntilStarted()
        async let second: Int = cache.value(for: "k", now: now, ttl: ttl) {
            await gate.markStartedAndWaitForRelease()
            throw CancellationError()
        }
        await gate.release()

        var errors: [Error] = []
        do { _ = try await first } catch { errors.append(error) }
        do { _ = try await second } catch { errors.append(error) }

        XCTAssertEqual(errors.count, 2, "neither caller may be handed the stale 7")
        for error in errors {
            XCTAssertTrue(error is CancellationError, "got \(error)")
        }
        let starts = await gate.startCount
        XCTAssertEqual(starts, 1, "the second caller must join the in-flight fetch, not start another")
    }

    /// A fetch that succeeds still populates both callers, so the coalescing
    /// itself is not broken by the cancellation handling.
    func testCoalescedCallersShareASuccessfulFetch() async throws {
        let cache = TTLCache<String, Int>()
        let gate = FetchGate()

        async let first: Int = cache.value(for: "k", now: now, ttl: ttl) {
            await Task.yield()
            await gate.markStartedAndWaitForRelease()
            return 42
        }
        await gate.waitUntilStarted()
        async let second: Int = cache.value(for: "k", now: now, ttl: ttl) {
            await gate.markStartedAndWaitForRelease()
            return 42
        }
        await gate.release()

        let values = try await [first, second]

        XCTAssertEqual(values, [42, 42])
        let starts = await gate.startCount
        XCTAssertEqual(starts, 1, "the second caller must join the in-flight fetch, not start another")
    }
}

/// Counts fetch entries and holds them until released, so a joiner provably
/// finds the first fetch in flight rather than racing it.
private actor FetchGate {

    private(set) var startCount = 0
    private var isReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func markStartedAndWaitForRelease() async {
        startCount += 1
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()

        guard !isReleased else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilStarted() async {
        guard startCount == 0 else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        isReleased = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}
