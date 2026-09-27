//
//  ArrayChunkedTests.swift
//  VultisigAppTests
//
//  `chunked(into:)` backs the rewards-history batched fetch: a batch must
//  stop scheduling the next one as soon as a confirmed gap is found, so the
//  batch size determines how many requests can be "wasted" past that point.
//

import XCTest
@testable import VultisigApp

final class ArrayChunkedTests: XCTestCase {

    func testEvenlyDivisibleCount() {
        XCTAssertEqual([1, 2, 3, 4].chunked(into: 2), [[1, 2], [3, 4]])
    }

    func testLastChunkIsShorter() {
        XCTAssertEqual([1, 2, 3, 4, 5].chunked(into: 2), [[1, 2], [3, 4], [5]])
    }

    func testEmptyArrayReturnsNoChunks() {
        XCTAssertEqual([Int]().chunked(into: 5), [])
    }

    func testSizeLargerThanCountReturnsOneChunk() {
        XCTAssertEqual([1, 2].chunked(into: 20), [[1, 2]])
    }

    func testNonPositiveSizeReturnsTheWholeArrayRatherThanLooping() {
        XCTAssertEqual([1, 2, 3].chunked(into: 0), [[1, 2, 3]])
        XCTAssertEqual([1, 2, 3].chunked(into: -1), [[1, 2, 3]])
    }

    /// Empty input is empty input — a non-positive size must not turn it
    /// into one chunk containing an empty array.
    func testEmptyArrayWithNonPositiveSizeStillReturnsNoChunks() {
        XCTAssertEqual([Int]().chunked(into: 0), [])
        XCTAssertEqual([Int]().chunked(into: -1), [])
    }
}
