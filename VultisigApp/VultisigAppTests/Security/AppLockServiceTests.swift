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
