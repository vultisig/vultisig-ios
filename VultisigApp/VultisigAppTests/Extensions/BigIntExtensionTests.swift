//
//  BigIntExtensionTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest
import BigInt

final class BigIntExtensionTests: XCTestCase {

    func test_median_ofEmptyArray_isNil() {
        XCTAssertNil([BigInt]().median())
    }

    func test_median_ofSingleElementArray_isThatElement() {
        XCTAssertEqual([BigInt(500)].median(), BigInt(500))
    }

    func test_median_ofOddLengthArray_isTheMiddleElement() {
        let samples = [100, 200, 300].map { BigInt($0) }
        XCTAssertEqual(samples.median(), BigInt(200))
    }

    func test_median_ofEvenLengthArray_averagesTheTwoCentralElements() {
        // Regression case: the upper-middle element (800) is wrong; the true median is
        // (200+800)/2 = 500.
        let samples = [100, 200, 800, 900].map { BigInt($0) }
        XCTAssertEqual(samples.median(), BigInt(500))
    }

    func test_median_ofTwoElements_averagesBoth() {
        let samples = [100, 300].map { BigInt($0) }
        XCTAssertEqual(samples.median(), BigInt(200))
    }

    func test_median_ofEvenLengthArrayWithOddSum_truncatesDownInsteadOfRounding() {
        let samples = [100, 100, 201, 300].map { BigInt($0) }
        // (100 + 201) / 2 = 150 (BigInt division truncates toward zero for non-negative values).
        XCTAssertEqual(samples.median(), BigInt(150))
    }

    func test_median_ofTenElementArray_matchesTheRealGetFeeHistoryWindowShape() {
        // eth_feeHistory is always requested with a fixed 10-block window.
        let samples = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100].map { BigInt($0) }
        XCTAssertEqual(samples.median(), BigInt(55)) // avg(50, 60) = 55
    }

    func test_median_ofLargeValues_doesNotOverflow() {
        let samples = [BigInt("9999999999999999999"), BigInt("10000000000000000001")]
        XCTAssertEqual(samples.median(), BigInt("10000000000000000000"))
    }
}
