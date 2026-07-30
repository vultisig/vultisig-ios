//
//  AppReviewPolicyTests.swift
//  VultisigAppTests
//
//  Exhaustive coverage of the review throttle: each rule in isolation,
//  each boundary (exactly 3 transactions, exactly 7 days, exactly 120
//  days) and the combined gate. Every date is pinned — the policy takes
//  `now` as a parameter, so nothing here sleeps.
//

import XCTest
@testable import VultisigApp

final class AppReviewPolicyTests: XCTestCase {

    private let day: TimeInterval = 24 * 60 * 60
    private let installed = Date(timeIntervalSince1970: 1_700_000_000)

    /// A state that satisfies every rule, so each test can break exactly one.
    private func eligibleState() -> AppReviewState {
        AppReviewState(
            confirmedTransactionCount: 3,
            installDate: installed,
            lastPromptDate: nil
        )
    }

    private func now(daysAfterInstall days: Double) -> Date {
        installed.addingTimeInterval(days * day)
    }

    // MARK: - Combined gate

    func testPromptsWhenEveryRuleIsSatisfied() {
        XCTAssertTrue(
            AppReviewPolicy.shouldRequestReview(
                state: eligibleState(),
                now: now(daysAfterInstall: 7)
            )
        )
    }

    func testDoesNotPromptWhenEveryRuleFails() {
        let state = AppReviewState(
            confirmedTransactionCount: 0,
            installDate: installed,
            lastPromptDate: installed
        )
        XCTAssertFalse(
            AppReviewPolicy.shouldRequestReview(state: state, now: now(daysAfterInstall: 1))
        )
    }

    // MARK: - Transaction count

    func testDoesNotPromptBelowTransactionThreshold() {
        var state = eligibleState()
        state.confirmedTransactionCount = 2
        XCTAssertFalse(
            AppReviewPolicy.shouldRequestReview(state: state, now: now(daysAfterInstall: 30))
        )
    }

    func testPromptsAtExactlyThreeTransactions() {
        var state = eligibleState()
        state.confirmedTransactionCount = 3
        XCTAssertTrue(
            AppReviewPolicy.shouldRequestReview(state: state, now: now(daysAfterInstall: 30))
        )
    }

    func testPromptsAboveTransactionThreshold() {
        var state = eligibleState()
        state.confirmedTransactionCount = 50
        XCTAssertTrue(
            AppReviewPolicy.shouldRequestReview(state: state, now: now(daysAfterInstall: 30))
        )
    }

    func testDoesNotPromptWithZeroTransactions() {
        var state = eligibleState()
        state.confirmedTransactionCount = 0
        XCTAssertFalse(
            AppReviewPolicy.shouldRequestReview(state: state, now: now(daysAfterInstall: 30))
        )
    }

    // MARK: - Install age

    func testDoesNotPromptBeforeSevenDaysSinceInstall() {
        XCTAssertFalse(
            AppReviewPolicy.shouldRequestReview(
                state: eligibleState(),
                now: installed.addingTimeInterval(7 * day - 1)
            )
        )
    }

    func testPromptsAtExactlySevenDaysSinceInstall() {
        XCTAssertTrue(
            AppReviewPolicy.shouldRequestReview(
                state: eligibleState(),
                now: installed.addingTimeInterval(7 * day)
            )
        )
    }

    func testDoesNotPromptWithoutAnInstallDate() {
        var state = eligibleState()
        state.installDate = nil
        XCTAssertFalse(
            AppReviewPolicy.shouldRequestReview(state: state, now: now(daysAfterInstall: 365))
        )
    }

    func testDoesNotPromptWhenInstallDateIsInTheFuture() {
        var state = eligibleState()
        state.installDate = now(daysAfterInstall: 30)
        XCTAssertFalse(
            AppReviewPolicy.shouldRequestReview(state: state, now: installed)
        )
    }

    // MARK: - Prompt cooldown

    func testDoesNotPromptBeforeOneHundredTwentyDaysSinceLastPrompt() {
        var state = eligibleState()
        state.lastPromptDate = now(daysAfterInstall: 10)
        XCTAssertFalse(
            AppReviewPolicy.shouldRequestReview(
                state: state,
                now: now(daysAfterInstall: 10).addingTimeInterval(120 * day - 1)
            )
        )
    }

    func testPromptsAtExactlyOneHundredTwentyDaysSinceLastPrompt() {
        var state = eligibleState()
        state.lastPromptDate = now(daysAfterInstall: 10)
        XCTAssertTrue(
            AppReviewPolicy.shouldRequestReview(
                state: state,
                now: now(daysAfterInstall: 10).addingTimeInterval(120 * day)
            )
        )
    }

    func testPromptsWhenNeverPromptedBefore() {
        var state = eligibleState()
        state.lastPromptDate = nil
        XCTAssertTrue(
            AppReviewPolicy.shouldRequestReview(state: state, now: now(daysAfterInstall: 7))
        )
    }

    func testDoesNotPromptWhenLastPromptIsInTheFuture() {
        var state = eligibleState()
        state.lastPromptDate = now(daysAfterInstall: 400)
        XCTAssertFalse(
            AppReviewPolicy.shouldRequestReview(state: state, now: now(daysAfterInstall: 30))
        )
    }

    // MARK: - One failing rule vetoes the rest

    func testTransactionCountVetoesAnOtherwiseEligibleState() {
        var state = eligibleState()
        state.confirmedTransactionCount = 2
        state.lastPromptDate = nil
        XCTAssertFalse(
            AppReviewPolicy.shouldRequestReview(state: state, now: now(daysAfterInstall: 1_000))
        )
    }

    func testInstallAgeVetoesAnOtherwiseEligibleState() {
        var state = eligibleState()
        state.confirmedTransactionCount = 100
        XCTAssertFalse(
            AppReviewPolicy.shouldRequestReview(state: state, now: now(daysAfterInstall: 6))
        )
    }

    func testCooldownVetoesAnOtherwiseEligibleState() {
        var state = eligibleState()
        state.confirmedTransactionCount = 100
        state.lastPromptDate = now(daysAfterInstall: 100)
        XCTAssertFalse(
            AppReviewPolicy.shouldRequestReview(state: state, now: now(daysAfterInstall: 200))
        )
    }

    // MARK: - Thresholds

    func testThresholdsMatchTheAgreedPolicy() {
        XCTAssertEqual(AppReviewPolicy.minimumConfirmedTransactions, 3)
        XCTAssertEqual(AppReviewPolicy.minimumTimeSinceInstall, 7 * day)
        XCTAssertEqual(AppReviewPolicy.minimumTimeBetweenPrompts, 120 * day)
    }
}
