//
//  ThreadSafeDictionaryTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class ThreadSafeDictionaryTests: XCTestCase {
    /// Past the dictionary's 1,000-entry preallocation, so the writes also
    /// grow its storage.
    private static let keyCount = 5_000
    private static let rounds = 10

    private final class Counter: @unchecked Sendable {
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

    func testConcurrentSetSyncKeepsEveryWriteAndPublishesItOnReturn() {
        for _ in 0..<Self.rounds {
            let sut = ThreadSafeDictionary<Int, Int>()
            let unreadWrites = Counter()

            DispatchQueue.concurrentPerform(iterations: Self.keyCount) { key in
                sut.setSync(key, key)
                if sut.get(key) != key {
                    unreadWrites.increment()
                }
                // A snapshot shares the storage, so the next write has to
                // copy it while other writers are still running.
                if key.isMultiple(of: 64) {
                    _ = sut.allItems()
                }
            }

            let items = sut.allItems()
            let wrongKeys = (0..<Self.keyCount).filter { items[$0] != $0 }.count
            XCTAssertEqual(unreadWrites.value, 0, "A write must be readable as soon as setSync returns")
            XCTAssertEqual(items.count, Self.keyCount)
            XCTAssertEqual(wrongKeys, 0, "Concurrent setSync calls must not lose or corrupt entries")
        }
    }
}
