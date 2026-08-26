//
//  AppReviewPolicyTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class AppReviewPolicyTests: XCTestCase {
    private let day: TimeInterval = 24 * 60 * 60
    private let installed = Date(timeIntervalSince1970: 1_700_000_000)

    private func eligibleState() -> AppReviewState {
        AppReviewState(
            qualifyingEventCount: 2,
            installDate: installed,
            lastPromptDate: nil,
            lastPromptedVersion: nil
        )
    }

    private func now(daysAfterInstall days: Double) -> Date {
        installed.addingTimeInterval(days * day)
    }

    func testPromptsWhenEveryRuleIsSatisfied() {
        XCTAssertTrue(
            AppReviewPolicy.shouldRequestReview(
                state: eligibleState(),
                now: now(daysAfterInstall: 7),
                currentVersion: "1.2.3"
            )
        )
    }

    func testDoesNotPromptBelowTwoEvents() {
        var state = eligibleState()
        state.qualifyingEventCount = 1
        XCTAssertFalse(
            AppReviewPolicy.shouldRequestReview(
                state: state,
                now: now(daysAfterInstall: 30),
                currentVersion: "1.2.3"
            )
        )
    }

    func testPromptsAtExactlyTwoEvents() {
        var state = eligibleState()
        state.qualifyingEventCount = 2
        XCTAssertTrue(
            AppReviewPolicy.shouldRequestReview(
                state: state,
                now: now(daysAfterInstall: 30),
                currentVersion: "1.2.3"
            )
        )
    }

    func testDoesNotPromptBeforeSevenDaysSinceInstall() {
        XCTAssertFalse(
            AppReviewPolicy.shouldRequestReview(
                state: eligibleState(),
                now: installed.addingTimeInterval(7 * day - 1),
                currentVersion: "1.2.3"
            )
        )
    }

    func testPromptsAtExactlySevenDaysSinceInstall() {
        XCTAssertTrue(
            AppReviewPolicy.shouldRequestReview(
                state: eligibleState(),
                now: installed.addingTimeInterval(7 * day),
                currentVersion: "1.2.3"
            )
        )
    }

    func testDoesNotPromptWithoutInstallDate() {
        var state = eligibleState()
        state.installDate = nil
        XCTAssertFalse(
            AppReviewPolicy.shouldRequestReview(
                state: state,
                now: now(daysAfterInstall: 365),
                currentVersion: "1.2.3"
            )
        )
    }

    func testDoesNotPromptWhenInstallDateIsInFuture() {
        var state = eligibleState()
        state.installDate = now(daysAfterInstall: 30)
        XCTAssertFalse(
            AppReviewPolicy.shouldRequestReview(
                state: state,
                now: installed,
                currentVersion: "1.2.3"
            )
        )
    }

    func testDoesNotPromptWithoutCurrentVersion() {
        XCTAssertFalse(
            AppReviewPolicy.shouldRequestReview(
                state: eligibleState(),
                now: now(daysAfterInstall: 30),
                currentVersion: nil
            )
        )
        XCTAssertFalse(
            AppReviewPolicy.shouldRequestReview(
                state: eligibleState(),
                now: now(daysAfterInstall: 30),
                currentVersion: ""
            )
        )
    }

    func testDoesNotPromptTwiceForSameVersion() {
        var state = eligibleState()
        state.lastPromptDate = now(daysAfterInstall: 7)
        state.lastPromptedVersion = "1.2.3"

        XCTAssertFalse(
            AppReviewPolicy.shouldRequestReview(
                state: state,
                now: now(daysAfterInstall: 365),
                currentVersion: "1.2.3"
            )
        )
    }

    func testDoesNotPromptNewVersionBeforeFourteenDayFloor() {
        var state = eligibleState()
        state.lastPromptDate = now(daysAfterInstall: 7)
        state.lastPromptedVersion = "1.2.3"

        XCTAssertFalse(
            AppReviewPolicy.shouldRequestReview(
                state: state,
                now: now(daysAfterInstall: 7).addingTimeInterval(14 * day - 1),
                currentVersion: "1.2.4"
            )
        )
    }

    func testPromptsNewVersionAtExactlyFourteenDayFloor() {
        var state = eligibleState()
        state.lastPromptDate = now(daysAfterInstall: 7)
        state.lastPromptedVersion = "1.2.3"

        XCTAssertTrue(
            AppReviewPolicy.shouldRequestReview(
                state: state,
                now: now(daysAfterInstall: 21),
                currentVersion: "1.2.4"
            )
        )
    }

    func testDoesNotPromptWhenLastPromptDateIsInFuture() {
        var state = eligibleState()
        state.lastPromptDate = now(daysAfterInstall: 400)
        state.lastPromptedVersion = "1.2.2"
        XCTAssertFalse(
            AppReviewPolicy.shouldRequestReview(
                state: state,
                now: now(daysAfterInstall: 30),
                currentVersion: "1.2.3"
            )
        )
    }

    func testThresholdsMatchAgreedPolicy() {
        XCTAssertEqual(AppReviewPolicy.minimumQualifyingEvents, 2)
        XCTAssertEqual(AppReviewPolicy.minimumTimeSinceInstall, 7 * day)
        XCTAssertEqual(AppReviewPolicy.minimumTimeBetweenPrompts, 14 * day)
    }
}
