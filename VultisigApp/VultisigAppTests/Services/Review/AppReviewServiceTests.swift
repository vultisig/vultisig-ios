//
//  AppReviewServiceTests.swift
//  VultisigAppTests
//
//  Persistence + idempotency coverage for the review throttle's state
//  layer. Each test gets its own `UserDefaults` suite so nothing touches
//  `.standard`, and the clock is injected so the 7-day / 120-day windows
//  are crossed by moving a variable, never by sleeping.
//

import XCTest
@testable import VultisigApp

@MainActor
final class AppReviewServiceTests: XCTestCase {

    private let day: TimeInterval = 24 * 60 * 60
    private var suiteName = ""
    private var defaults = UserDefaults.standard
    private var clock = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "AppReviewServiceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        clock = Date(timeIntervalSince1970: 1_700_000_000)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private func makeService() -> AppReviewService {
        AppReviewService(defaults: defaults, now: { [unowned self] in self.clock })
    }

    private func advance(days: Double) {
        clock = clock.addingTimeInterval(days * day)
    }

    // MARK: - Install date seeding

    func testSeedInstallDateStoresTheCurrentDate() {
        let service = makeService()
        service.seedInstallDateIfNeeded()
        XCTAssertEqual(service.state.installDate, clock)
    }

    func testSeedInstallDateIsWrittenOnlyOnce() {
        let service = makeService()
        service.seedInstallDateIfNeeded()
        let seeded = clock

        advance(days: 30)
        service.seedInstallDateIfNeeded()

        XCTAssertEqual(service.state.installDate, seeded)
    }

    func testInstallDateIsNilBeforeSeeding() {
        XCTAssertNil(makeService().state.installDate)
    }

    func testInstallDateSurvivesANewServiceInstance() {
        let first = makeService()
        first.seedInstallDateIfNeeded()

        advance(days: 5)
        let second = makeService()
        second.seedInstallDateIfNeeded()

        XCTAssertEqual(second.state.installDate, first.state.installDate)
    }

    // MARK: - Counting

    func testRecordingIncrementsTheCount() {
        let service = makeService()
        XCTAssertTrue(service.recordConfirmedTransaction(id: "hash-a"))
        XCTAssertTrue(service.recordConfirmedTransaction(id: "hash-b"))
        XCTAssertEqual(service.state.confirmedTransactionCount, 2)
    }

    /// The main correctness risk: the done screen can observe the same
    /// `.confirmed` status repeatedly, so re-recording one hash must be inert.
    func testRepeatedObservationsOfTheSameTransactionCountOnce() {
        let service = makeService()
        XCTAssertTrue(service.recordConfirmedTransaction(id: "hash-a"))
        XCTAssertFalse(service.recordConfirmedTransaction(id: "hash-a"))
        XCTAssertFalse(service.recordConfirmedTransaction(id: "hash-a"))
        XCTAssertEqual(service.state.confirmedTransactionCount, 1)
    }

    /// A remount builds a fresh service against the same defaults; the
    /// duplicate check has to survive that, not just live in memory.
    func testDuplicateSuppressionSurvivesANewServiceInstance() {
        makeService().recordConfirmedTransaction(id: "hash-a")
        let remounted = makeService()

        XCTAssertFalse(remounted.recordConfirmedTransaction(id: "hash-a"))
        XCTAssertEqual(remounted.state.confirmedTransactionCount, 1)
    }

    func testEmptyTransactionIDIsNotCounted() {
        let service = makeService()
        XCTAssertFalse(service.recordConfirmedTransaction(id: ""))
        XCTAssertFalse(service.recordConfirmedTransaction(id: ""))
        XCTAssertEqual(service.state.confirmedTransactionCount, 0)
    }

    func testCountedTransactionIDsAreBounded() {
        let service = makeService()
        let overflow = AppReviewService.countedTransactionIDLimit + 10
        for index in 0..<overflow {
            XCTAssertTrue(service.recordConfirmedTransaction(id: "hash-\(index)"))
        }

        XCTAssertEqual(service.state.confirmedTransactionCount, overflow)
        let stored = defaults.stringArray(forKey: "appReview.countedTransactionIDs") ?? []
        XCTAssertEqual(stored.count, AppReviewService.countedTransactionIDLimit)
        // Oldest hashes are evicted first; the most recent ones stay guarded.
        XCTAssertFalse(stored.contains("hash-0"))
        XCTAssertTrue(stored.contains("hash-\(overflow - 1)"))
    }

    func testCountSurvivesANewServiceInstance() {
        makeService().recordConfirmedTransaction(id: "hash-a")
        makeService().recordConfirmedTransaction(id: "hash-b")
        XCTAssertEqual(makeService().state.confirmedTransactionCount, 2)
    }

    // MARK: - Prompt recording

    func testRecordPromptShownStoresTheCurrentDate() {
        let service = makeService()
        XCTAssertNil(service.state.lastPromptDate)

        service.recordPromptShown()
        XCTAssertEqual(service.state.lastPromptDate, clock)
    }

    func testRecordPromptShownOverwritesThePreviousDate() {
        let service = makeService()
        service.recordPromptShown()

        advance(days: 200)
        service.recordPromptShown()

        XCTAssertEqual(service.state.lastPromptDate, clock)
    }

    // MARK: - End-to-end throttle

    func testDoesNotAskBeforeTheThresholdsAreMet() {
        let service = makeService()
        service.seedInstallDateIfNeeded()

        service.recordConfirmedTransaction(id: "hash-a")
        service.recordConfirmedTransaction(id: "hash-b")
        advance(days: 10)
        XCTAssertFalse(service.shouldRequestReview(), "two transactions is below the threshold")

        service.recordConfirmedTransaction(id: "hash-c")
        XCTAssertTrue(service.shouldRequestReview())
    }

    func testDoesNotAskWithinTheFirstWeek() {
        let service = makeService()
        service.seedInstallDateIfNeeded()

        for id in ["hash-a", "hash-b", "hash-c"] {
            service.recordConfirmedTransaction(id: id)
        }

        advance(days: 6)
        XCTAssertFalse(service.shouldRequestReview())

        advance(days: 1)
        XCTAssertTrue(service.shouldRequestReview())
    }

    func testAskingClosesTheWindowForOneHundredTwentyDays() {
        let service = makeService()
        service.seedInstallDateIfNeeded()
        for id in ["hash-a", "hash-b", "hash-c"] {
            service.recordConfirmedTransaction(id: id)
        }
        advance(days: 7)
        XCTAssertTrue(service.shouldRequestReview())

        service.recordPromptShown()
        XCTAssertFalse(service.shouldRequestReview())

        advance(days: 119)
        service.recordConfirmedTransaction(id: "hash-d")
        XCTAssertFalse(service.shouldRequestReview())

        advance(days: 1)
        XCTAssertTrue(service.shouldRequestReview())
    }

    /// Re-observing the same three hashes must not push a two-transaction
    /// user over the threshold.
    func testRepeatedObservationsDoNotUnlockThePromptEarly() {
        let service = makeService()
        service.seedInstallDateIfNeeded()
        advance(days: 30)

        for _ in 0..<5 {
            service.recordConfirmedTransaction(id: "hash-a")
            service.recordConfirmedTransaction(id: "hash-b")
        }

        XCTAssertEqual(service.state.confirmedTransactionCount, 2)
        XCTAssertFalse(service.shouldRequestReview())
    }

    // MARK: - Claiming the ask

    /// Brings a service to the point where only a fresh transaction is
    /// missing: seeded, past the 7-day wait, two transactions counted.
    private func makeAlmostEligibleService() -> AppReviewService {
        let service = makeService()
        service.seedInstallDateIfNeeded()
        service.recordConfirmedTransaction(id: "hash-a")
        service.recordConfirmedTransaction(id: "hash-b")
        advance(days: 30)
        return service
    }

    func testClaimingAsksOnceTheThirdTransactionConfirms() {
        let service = makeAlmostEligibleService()
        XCTAssertTrue(service.claimReviewPrompt(forConfirmedTransaction: "hash-c"))
        XCTAssertEqual(service.state.lastPromptDate, clock)
    }

    /// The ask must follow a *newly counted* transaction. Re-observing a hash
    /// that already counted has no transaction behind it, so it must not ask
    /// even when every throttle rule is otherwise satisfied.
    func testClaimingRequiresANewlyCountedTransaction() {
        let service = makeAlmostEligibleService()
        XCTAssertTrue(service.claimReviewPrompt(forConfirmedTransaction: "hash-c"))

        advance(days: 200)
        XCTAssertFalse(
            service.claimReviewPrompt(forConfirmedTransaction: "hash-c"),
            "a repeat observation of an already-counted hash must not ask again"
        )
    }

    /// The custom-message signing flow renders the done screen already
    /// `.confirmed` with an empty hash. Signing a message is not a
    /// transaction, so it must never spend an ask.
    func testClaimingWithAnEmptyIDNeverAsks() {
        let service = makeAlmostEligibleService()
        service.recordConfirmedTransaction(id: "hash-c")

        XCTAssertTrue(service.shouldRequestReview(), "the throttle is otherwise satisfied")
        XCTAssertFalse(service.claimReviewPrompt(forConfirmedTransaction: ""))
        XCTAssertNil(service.state.lastPromptDate)
    }

    func testClaimingDoesNotSpendTheAskWhenTheThrottleRefuses() {
        let service = makeService()
        service.seedInstallDateIfNeeded()

        XCTAssertFalse(service.claimReviewPrompt(forConfirmedTransaction: "hash-a"))
        XCTAssertNil(service.state.lastPromptDate)
        XCTAssertEqual(service.state.confirmedTransactionCount, 1, "the transaction still counts")
    }

    func testClaimingClosesTheWindowForOneHundredTwentyDays() {
        let service = makeAlmostEligibleService()
        XCTAssertTrue(service.claimReviewPrompt(forConfirmedTransaction: "hash-c"))

        advance(days: 119)
        XCTAssertFalse(service.claimReviewPrompt(forConfirmedTransaction: "hash-d"))

        advance(days: 1)
        XCTAssertTrue(service.claimReviewPrompt(forConfirmedTransaction: "hash-e"))
    }

    func testStateIsIsolatedPerDefaultsSuite() {
        let service = makeService()
        service.seedInstallDateIfNeeded()
        service.recordConfirmedTransaction(id: "hash-a")

        let otherSuiteName = "AppReviewServiceTests-other-\(UUID().uuidString)"
        let otherDefaults = UserDefaults(suiteName: otherSuiteName)!
        defer { otherDefaults.removePersistentDomain(forName: otherSuiteName) }
        let other = AppReviewService(defaults: otherDefaults, now: { [unowned self] in self.clock })

        XCTAssertEqual(other.state.confirmedTransactionCount, 0)
        XCTAssertNil(other.state.installDate)
    }
}
