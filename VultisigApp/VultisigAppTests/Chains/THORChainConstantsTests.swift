//
//  THORChainConstantsTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class THORChainConstantsTests: XCTestCase {

    func testBlockTimeSecondsIsSixSecondsSinceLaunch() {
        XCTAssertEqual(THORChainConstants.blockTimeSeconds, 6)
    }

    func testBlocksPerHourIsDerivedFromBlockTime() {
        XCTAssertEqual(THORChainConstants.blocksPerHour, 600)
    }

    func testBlocksForHoursMatchesLimitSwapExpiryWindows() {
        XCTAssertEqual(THORChainConstants.blocks(forHours: 12), 7200)
        XCTAssertEqual(THORChainConstants.blocks(forHours: 24), 14400)
        XCTAssertEqual(THORChainConstants.blocks(forHours: 72), 43200)
    }
}
