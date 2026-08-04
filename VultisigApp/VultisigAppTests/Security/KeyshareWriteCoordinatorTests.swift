//
//  KeyshareWriteCoordinatorTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

/// Pins the exclusion rules the coordinator exists to enforce.
///
/// The properties that matter are asymmetric on purpose: a transition excludes
/// everything, while writes and episodes do not exclude each other — vault
/// creation must never be serialized against itself.
final class KeyshareWriteCoordinatorTests: XCTestCase {

    private var sut: KeyshareWriteCoordinator!

    override func setUp() {
        super.setUp()
        sut = KeyshareWriteCoordinator()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    private func assertBusy<T>(_ expression: @autoclosure () throws -> T, _ message: String = "") {
        XCTAssertThrowsError(try expression(), message) { error in
            XCTAssertEqual(error as? KeyshareWriteCoordinatorError, .busy, message)
        }
    }

    // MARK: - A transition excludes everything

    func testASecondTransitionIsRefused() throws {
        let first = try sut.beginTransition()

        assertBusy(try sut.beginTransition())

        sut.end(first)
    }

    func testATransitionSucceedsOnceTheFirstEnds() throws {
        let first = try sut.beginTransition()
        sut.end(first)

        let second = try sut.beginTransition()
        sut.end(second)
    }

    func testAWriteIsRefusedWhileATransitionIsHeld() throws {
        let lease = try sut.beginTransition()

        assertBusy(try sut.withWriteLease { })

        sut.end(lease)
    }

    func testAnEpisodeIsRefusedWhileATransitionIsHeld() throws {
        let lease = try sut.beginTransition()

        XCTAssertNil(sut.beginEpisode())

        sut.end(lease)
    }

    // MARK: - A transition waits for writes and episodes

    func testATransitionIsRefusedWhileAWriteIsInFlight() throws {
        var refused = false

        try sut.withWriteLease {
            do {
                _ = try sut.beginTransition()
            } catch {
                refused = (error as? KeyshareWriteCoordinatorError) == .busy
            }
        }

        XCTAssertTrue(refused, "A transition must not start while a share is being sealed and stored")
        let lease = try sut.beginTransition()
        sut.end(lease)
    }

    func testATransitionIsRefusedWhileAnEpisodeIsOpen() throws {
        let episode = try XCTUnwrap(sut.beginEpisode())

        assertBusy(try sut.beginTransition())

        sut.end(episode)
        let lease = try sut.beginTransition()
        sut.end(lease)
    }

    /// The interval a per-write counter misses: TSS produces a share long before
    /// the flow commits it, and only the episode covers that gap.
    func testATransitionIsRefusedUntilEveryOpenEpisodeEnds() throws {
        let first = try XCTUnwrap(sut.beginEpisode())
        let second = try XCTUnwrap(sut.beginEpisode())

        sut.end(first)
        assertBusy(try sut.beginTransition(), "One episode is still open")

        sut.end(second)
        let lease = try sut.beginTransition()
        sut.end(lease)
    }

    // MARK: - Writes and episodes do not exclude each other

    func testWritesNest() throws {
        var innerRan = false

        try sut.withWriteLease {
            try sut.withWriteLease { innerRan = true }
        }

        XCTAssertTrue(innerRan)
    }

    func testEpisodesDoNotExcludeEachOther() throws {
        let first = try XCTUnwrap(sut.beginEpisode())
        let second = try XCTUnwrap(sut.beginEpisode())

        sut.end(first)
        sut.end(second)
    }

    func testAWriteIsAllowedInsideAnEpisode() throws {
        let episode = try XCTUnwrap(sut.beginEpisode())

        let result = try sut.withWriteLease { 42 }

        XCTAssertEqual(result, 42)
        sut.end(episode)
    }

    // MARK: - Releasing

    func testAWriteLeaseIsReleasedWhenTheBodyThrows() {
        struct Boom: Error {}

        XCTAssertThrowsError(try sut.withWriteLease { throw Boom() })

        XCTAssertNoThrow(try sut.beginTransition(), "A thrown write must not strand the lease")
    }

    /// The property that makes a stranded lease impossible: an error path that
    /// forgets to call `end` still releases when the token goes out of scope.
    func testADroppedTransitionLeaseReleases() throws {
        do {
            _ = try sut.beginTransition()
        }

        let lease = try sut.beginTransition()
        sut.end(lease)
    }

    func testADroppedEpisodeLeaseReleases() throws {
        do {
            _ = sut.beginEpisode()
        }

        let lease = try sut.beginTransition()
        sut.end(lease)
    }

    func testEndingALeaseTwiceIsHarmless() throws {
        let first = try sut.beginTransition()

        sut.end(first)
        sut.end(first)

        // The second release must not have left the coordinator permanently
        // open: a fresh transition is available, and it still excludes another.
        let second = try sut.beginTransition()
        assertBusy(try sut.beginTransition(), "The second lease is still held")
        sut.end(second)
    }

    func testEndingAnEpisodeTwiceDoesNotUndercountOpenEpisodes() throws {
        let first = try XCTUnwrap(sut.beginEpisode())
        let second = try XCTUnwrap(sut.beginEpisode())

        sut.end(first)
        sut.end(first)

        assertBusy(try sut.beginTransition(), "One episode is still open")
        sut.end(second)
    }

    // MARK: - Concurrency

    /// Reached synchronously from TSS callbacks on arbitrary threads, so the
    /// counters have to survive contention.
    func testConcurrentWritesAllRunAndAllRelease() throws {
        let counter = Counter()

        DispatchQueue.concurrentPerform(iterations: 500) { _ in
            try? self.sut.withWriteLease { counter.increment() }
        }

        XCTAssertEqual(counter.value, 500)
        let lease = try sut.beginTransition()
        sut.end(lease)
    }

    func testConcurrentEpisodesAllAcquireAndAllRelease() throws {
        let acquired = Counter()

        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            guard let episode = self.sut.beginEpisode() else { return }
            acquired.increment()
            self.sut.end(episode)
        }

        XCTAssertEqual(acquired.value, 200, "Episodes must not refuse each other")
        let lease = try sut.beginTransition()
        sut.end(lease)
    }

    /// `release()` reaches back into the coordinator, and `NSLock` is not
    /// recursive — so a lease deallocated while another coordinator call is on
    /// the same stack must not deadlock.
    func testALeaseDeallocatedInsideAWriteBodyDoesNotDeadlock() throws {
        try sut.withWriteLease {
            _ = sut.beginEpisode()
        }

        let lease = try sut.beginTransition()
        sut.end(lease)
    }

    func testAnEpisodeDeallocatedWhileAWriteRunsReleases() throws {
        var episode = sut.beginEpisode()
        XCTAssertNotNil(episode)

        try sut.withWriteLease { episode = nil }

        XCTAssertNil(episode)
        let lease = try sut.beginTransition()
        sut.end(lease)
    }

    /// Releases and acquisitions racing each other must leave the flag coherent
    /// rather than stuck open or stuck closed.
    func testConcurrentTransitionAttemptsLeaveTheCoordinatorUsable() throws {
        let granted = Counter()

        DispatchQueue.concurrentPerform(iterations: 500) { _ in
            guard let lease = try? self.sut.beginTransition() else { return }
            granted.increment()
            self.sut.end(lease)
        }

        XCTAssertGreaterThan(granted.value, 0, "At least one attempt must win")
        let lease = try sut.beginTransition()
        assertBusy(try sut.beginTransition(), "Exclusion must still hold after the race")
        sut.end(lease)
    }

    /// Under contention every write either runs or is refused, and no write ever
    /// runs while the transition is held — the invariant the whole type exists
    /// for.
    func testNoWriteRunsWhileATransitionIsHeld() throws {
        let lease = try sut.beginTransition()
        let counter = Counter()

        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            try? self.sut.withWriteLease { counter.increment() }
        }

        XCTAssertEqual(counter.value, 0)
        sut.end(lease)
        XCTAssertEqual(try sut.withWriteLease { 1 }, 1)
    }
}

/// Minimal thread-safe counter — `DispatchQueue.concurrentPerform` bodies race
/// on a plain `Int`.
private final class Counter {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
