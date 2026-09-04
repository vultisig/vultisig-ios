//
//  AppLockServiceTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class AppLockServiceTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var sut: AppLockService!

    private let formatter = ISO8601DateFormatter()
    private let backgroundedAt = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "AppLockServiceTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        sut = AppLockService(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func recordBackgrounded(_ date: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        sut.noteBackgrounded(now: date)
    }

    private func foreground(after seconds: TimeInterval) -> Bool {
        sut.shouldRelock(now: backgroundedAt.addingTimeInterval(seconds))
    }

    // MARK: - Mode defaults preserve existing behaviour

    func testDefaultsToDeviceAuthOnAFreshInstall() {
        XCTAssertEqual(sut.mode, .deviceAuth)
    }

    /// Anyone upgrading with the legacy flag turned off — which the app does
    /// programmatically when biometrics are unavailable — must not suddenly find
    /// themselves gated.
    func testFallsBackToTheLegacyFlagWhenNoModeHasBeenChosen() {
        defaults.set(false, forKey: "isAuthenticationEnabled")

        XCTAssertEqual(sut.mode, .off)
    }

    func testLegacyFlagTrueMapsToDeviceAuth() {
        defaults.set(true, forKey: "isAuthenticationEnabled")

        XCTAssertEqual(sut.mode, .deviceAuth)
    }

    func testAnExplicitModeWinsOverTheLegacyFlag() {
        defaults.set(false, forKey: "isAuthenticationEnabled")

        sut.mode = .passcode

        XCTAssertEqual(sut.mode, .passcode)
    }

    func testModePersists() {
        sut.mode = .off

        XCTAssertEqual(AppLockService(defaults: defaults).mode, .off)
    }

    // MARK: - Interval

    func testDefaultIntervalMatchesThePreviouslyHardcodedFiveMinutes() {
        XCTAssertEqual(sut.autoLockInterval, .fiveMinutes)
        XCTAssertEqual(sut.autoLockInterval.duration, 300)
    }

    func testIntervalPersists() {
        sut.autoLockInterval = .thirtyMinutes

        XCTAssertEqual(AppLockService(defaults: defaults).autoLockInterval, .thirtyMinutes)
    }

    func testUnrecognisedStoredIntervalFallsBackToTheDefault() {
        defaults.set(7, forKey: "autoLockIntervalMinutes")

        XCTAssertEqual(sut.autoLockInterval, .fiveMinutes)
    }

    func testUnrecognisedSecondsValueDoesNotResurrectLegacyChoice() {
        defaults.set(123, forKey: "autoLockIntervalSeconds")
        defaults.set(15, forKey: "autoLockIntervalMinutes")

        XCTAssertEqual(sut.autoLockInterval, .fiveMinutes)
    }

    func testPersistsShortIntervalsInSeconds() {
        sut.autoLockInterval = .fifteenSeconds

        XCTAssertEqual(defaults.integer(forKey: "autoLockIntervalSeconds"), 15)
        XCTAssertEqual(AppLockService(defaults: defaults).autoLockInterval, .fifteenSeconds)
        XCTAssertNil(defaults.object(forKey: "autoLockIntervalMinutes"))
    }

    func testMirrorsCompatibleSelectionsForDowngradeSafety() {
        sut.autoLockInterval = .tenMinutes

        XCTAssertEqual(defaults.integer(forKey: "autoLockIntervalMinutes"), 10)
    }

    func testNeverRemovesLegacySelectionForDowngradeSafety() {
        defaults.set(15, forKey: "autoLockIntervalMinutes")

        sut.autoLockInterval = .never

        XCTAssertNil(defaults.object(forKey: "autoLockIntervalMinutes"))
    }

    func testNeverDurationCannotBeMistakenForAnExpiredInterval() {
        XCTAssertEqual(AutoLockInterval.never.duration, .infinity)
    }

    func testPickerCasesContainOnlyNewOptionsForANewSelection() {
        XCTAssertEqual(
            AutoLockInterval.pickerCases(current: .fiveMinutes),
            AutoLockInterval.selectableCases
        )
        XCTAssertTrue(AutoLockInterval.selectableCases.contains(.default))
        XCTAssertFalse(AutoLockInterval.selectableCases.contains(.immediate))
        XCTAssertFalse(AutoLockInterval.selectableCases.contains(.fifteenMinutes))
    }

    func testPickerCasesKeepMigratedLegacySelectionVisible() {
        XCTAssertEqual(
            AutoLockInterval.pickerCases(current: .fifteenMinutes),
            [.fifteenMinutes] + AutoLockInterval.selectableCases
        )
    }

    func testMigratesEveryPreviouslySelectableIntervalExactly() {
        let legacyValues: [(minutes: Int, expected: AutoLockInterval)] = [
            (0, .immediate),
            (1, .oneMinute),
            (5, .fiveMinutes),
            (10, .tenMinutes),
            (15, .fifteenMinutes),
            (30, .thirtyMinutes)
        ]

        for value in legacyValues {
            defaults.removeObject(forKey: "autoLockIntervalSeconds")
            defaults.set(value.minutes, forKey: "autoLockIntervalMinutes")
            XCTAssertEqual(sut.autoLockInterval, value.expected)
        }
    }

    func testSecondsValueWinsOverLegacyMinutes() {
        defaults.set(30, forKey: "autoLockIntervalSeconds")
        defaults.set(15, forKey: "autoLockIntervalMinutes")

        XCTAssertEqual(sut.autoLockInterval, .thirtySeconds)
    }

    // MARK: - Relock decision

    func testDoesNotRelockBeforeTheIntervalElapses() {
        recordBackgrounded()

        XCTAssertFalse(foreground(after: 299))
    }

    /// The behaviour this replaced used a strict `>`, so exactly the interval
    /// does not re-lock.
    func testDoesNotRelockExactlyAtTheInterval() {
        recordBackgrounded()

        XCTAssertFalse(foreground(after: 300))
    }

    func testRelocksAfterTheIntervalElapses() {
        recordBackgrounded()

        XCTAssertTrue(foreground(after: 301))
    }

    func testHonoursAShorterInterval() {
        sut.autoLockInterval = .oneMinute
        recordBackgrounded()

        XCTAssertFalse(foreground(after: 60))
        XCTAssertTrue(foreground(after: 61))
    }

    func testHonoursFifteenSecondInterval() {
        sut.autoLockInterval = .fifteenSeconds
        recordBackgrounded()

        XCTAssertFalse(foreground(after: 15))
        XCTAssertTrue(foreground(after: 16))
    }

    func testHonoursALongerInterval() {
        sut.autoLockInterval = .thirtyMinutes
        recordBackgrounded()

        XCTAssertFalse(foreground(after: 1800))
        XCTAssertTrue(foreground(after: 1801))
    }

    func testImmediateRelocksAtOnce() {
        sut.autoLockInterval = .immediate
        recordBackgrounded()

        XCTAssertTrue(foreground(after: 0))
    }

    func testNeverDoesNotRelockAfterBackgrounding() {
        sut.autoLockInterval = .never
        recordBackgrounded()

        XCTAssertFalse(foreground(after: 100_000_000))
    }

    func testMovingTheClockBackwardsRelocks() {
        recordBackgrounded()

        XCTAssertTrue(foreground(after: -1))
    }

    func testNeverIgnoresMovingTheClockBackwards() {
        sut.autoLockInterval = .never
        recordBackgrounded()

        XCTAssertFalse(foreground(after: -1))
    }

    func testNeverRelocksWhenTheLockIsOff() {
        sut.mode = .off
        sut.autoLockInterval = .immediate
        recordBackgrounded()

        XCTAssertFalse(foreground(after: 100_000))
    }

    func testDoesNotRelockWhenNothingWasEverRecorded() {
        // A first launch is not a return from the background; gating on a
        // timestamp that never existed would lock the app for no reason.
        XCTAssertFalse(sut.shouldRelock(now: backgroundedAt))
    }

    func testPasscodeModeUsesTheSameTiming() {
        sut.mode = .passcode
        recordBackgrounded()

        XCTAssertFalse(foreground(after: 300))
        XCTAssertTrue(foreground(after: 301))
    }

    // MARK: - Foreground bookkeeping

    func testEvaluateForegroundReportsTheDecisionAndResetsTheClock() {
        recordBackgrounded()

        let first = sut.evaluateForeground(now: backgroundedAt.addingTimeInterval(301))
        // Timestamp is now the moment of that foreground, so a second check a
        // short time later must not re-lock again.
        let second = sut.shouldRelock(now: backgroundedAt.addingTimeInterval(400))

        XCTAssertTrue(first)
        XCTAssertFalse(second)
    }

    func testEvaluateForegroundRecordsEvenWhenItDoesNotRelock() {
        recordBackgrounded()

        XCTAssertFalse(sut.evaluateForeground(now: backgroundedAt.addingTimeInterval(10)))
        XCTAssertFalse(sut.shouldRelock(now: backgroundedAt.addingTimeInterval(310)))
    }
}
