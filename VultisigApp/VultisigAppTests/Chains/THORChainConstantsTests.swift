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

    func testBlocksPerMinuteIsWholeSoMinutesNeverRound() {
        // The custom-expiry picker's finest grain is one minute. If a minute
        // weren't a whole number of blocks, every custom duration would round.
        XCTAssertEqual(THORChainConstants.blocksPerMinute, 10)
        XCTAssertEqual(60 % THORChainConstants.blockTimeSeconds, 0)
    }

    func testMinutesAndBlocksRoundTripExactly() {
        for minutes in [1, 10, 90, 1440, 4320] {
            let blocks = THORChainConstants.blocks(forMinutes: minutes)
            XCTAssertEqual(THORChainConstants.minutes(forBlocks: blocks), minutes)
        }
    }

    func testDefaultLimitSwapMaxAgeIsThreeDays() {
        // THORChain's documented StreamingLimitSwapMaxAge default, and what
        // mainnet currently runs. Used as the fallback when the mimir fetch fails.
        XCTAssertEqual(THORChainConstants.defaultLimitSwapMaxAgeBlocks, 43_200)
        XCTAssertEqual(
            THORChainConstants.defaultLimitSwapMaxAgeBlocks,
            THORChainConstants.blocks(forHours: 72)
        )
    }

    func testMinLimitSwapAgeIsTenMinutes() {
        XCTAssertEqual(
            THORChainConstants.minLimitSwapAgeBlocks,
            THORChainConstants.blocks(forMinutes: 10)
        )
    }
}
