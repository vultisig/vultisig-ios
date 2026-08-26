//
//  AppReviewServiceTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

@MainActor
final class AppReviewServiceTests: XCTestCase {
    private let day: TimeInterval = 24 * 60 * 60
    private var suiteName = ""
    private var defaults = UserDefaults.standard
    private var clock = Date(timeIntervalSince1970: 1_700_000_000)
    private var version: String? = "1.2.3"

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "AppReviewServiceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        clock = Date(timeIntervalSince1970: 1_700_000_000)
        version = "1.2.3"
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private func makeService() -> AppReviewService {
        AppReviewService(
            defaults: defaults,
            now: { [unowned self] in self.clock },
            bundleVersion: { [unowned self] in self.version }
        )
    }

    private func advance(days: Double) {
        clock = clock.addingTimeInterval(days * day)
    }

    private func makeEligibleService() -> AppReviewService {
        let service = makeService()
        service.seedInstallDateIfNeeded()
        service.record(.vaultBackupCompleted(vaultID: "vault-a"))
        service.record(.devicePairingCompleted(sessionID: "session-a"))
        advance(days: 7)
        return service
    }

    func testSeedInstallDateStoresCurrentDateOnce() {
        let service = makeService()
        service.seedInstallDateIfNeeded()
        let seeded = clock

        advance(days: 30)
        service.seedInstallDateIfNeeded()

        XCTAssertEqual(service.state.installDate, seeded)
    }

    func testEachDistinctEventIncrementsCount() {
        let service = makeService()
        XCTAssertTrue(service.record(.confirmedOutboundTransaction(id: "hash-a")))
        XCTAssertTrue(service.record(.confirmedIncomingTransaction(id: "hash-b")))
        XCTAssertTrue(service.record(.vaultBackupCompleted(vaultID: "vault-a")))
        XCTAssertTrue(service.record(.vaultRestoreCompleted(vaultID: "vault-b")))
        XCTAssertTrue(service.record(.devicePairingCompleted(sessionID: "session-a")))
        XCTAssertEqual(service.state.qualifyingEventCount, 5)
    }

    func testRepeatedEventCountsOnceAcrossInstances() {
        XCTAssertTrue(makeService().record(.vaultBackupCompleted(vaultID: "vault-a")))
        XCTAssertFalse(makeService().record(.vaultBackupCompleted(vaultID: "vault-a")))
        XCTAssertEqual(makeService().state.qualifyingEventCount, 1)
    }

    func testSameIdentityInDifferentNamespacesCountsSeparately() {
        let service = makeService()
        XCTAssertTrue(service.record(.confirmedOutboundTransaction(id: "same")))
        XCTAssertTrue(service.record(.confirmedIncomingTransaction(id: "same")))
        XCTAssertEqual(service.state.qualifyingEventCount, 2)
    }

    func testBlankEventIdentityIsNotCounted() {
        let service = makeService()
        XCTAssertFalse(service.record(.confirmedOutboundTransaction(id: "")))
        XCTAssertFalse(service.record(.devicePairingCompleted(sessionID: "   ")))
        XCTAssertEqual(service.state.qualifyingEventCount, 0)
    }

    func testCountedEventIDsAreBounded() {
        let service = makeService()
        let overflow = AppReviewService.countedEventIDLimit + 10
        for index in 0..<overflow {
            XCTAssertTrue(service.record(.confirmedOutboundTransaction(id: "hash-\(index)")))
        }

        XCTAssertEqual(service.state.qualifyingEventCount, overflow)
        let stored = defaults.stringArray(forKey: "appReview.countedEventIDs") ?? []
        XCTAssertEqual(stored.count, AppReviewService.countedEventIDLimit)
        XCTAssertFalse(stored.contains("outbound:hash-0"))
        XCTAssertTrue(stored.contains("outbound:hash-\(overflow - 1)"))
    }

    func testLegacyTransactionStateMigratesWithoutLosingCountOrDedupe() {
        defaults.set(2, forKey: "appReview.confirmedTransactionCount")
        defaults.set(["hash-a", "hash-b"], forKey: "appReview.countedTransactionIDs")
        let service = makeService()

        XCTAssertEqual(service.state.qualifyingEventCount, 2)
        XCTAssertFalse(service.record(.confirmedOutboundTransaction(id: "hash-a")))
        XCTAssertTrue(service.record(.vaultBackupCompleted(vaultID: "vault-a")))
        XCTAssertEqual(service.state.qualifyingEventCount, 3)
    }

    func testLegacyPromptOlderThanFourteenDaysCanClaimCurrentVersion() {
        defaults.set(2, forKey: "appReview.confirmedTransactionCount")
        defaults.set(clock.addingTimeInterval(-30 * day).timeIntervalSince1970, forKey: "appReview.installDate")
        defaults.set(clock.addingTimeInterval(-15 * day).timeIntervalSince1970, forKey: "appReview.lastPromptDate")

        let service = makeService()
        XCTAssertNil(service.state.lastPromptedVersion)
        XCTAssertTrue(service.claimReviewPrompt())
        XCTAssertEqual(service.state.lastPromptedVersion, "1.2.3")
    }

    func testClaimPersistsVersionDateAndInstrumentation() {
        let service = makeEligibleService()
        XCTAssertTrue(service.claimReviewPrompt())

        XCTAssertEqual(service.state.lastPromptDate, clock)
        XCTAssertEqual(service.state.lastPromptedVersion, "1.2.3")
        XCTAssertEqual(
            service.instrumentation,
            AppReviewInstrumentation(policyEvaluationCount: 1, promptClaimCount: 1)
        )
    }

    func testRefusedClaimStillIncrementsPolicyEvaluationOnly() {
        let service = makeService()
        XCTAssertFalse(service.claimReviewPrompt())
        XCTAssertEqual(
            service.instrumentation,
            AppReviewInstrumentation(policyEvaluationCount: 1, promptClaimCount: 0)
        )
    }

    func testClaimCannotRepeatForSameVersion() {
        let service = makeEligibleService()
        XCTAssertTrue(service.claimReviewPrompt())
        advance(days: 100)
        XCTAssertFalse(service.claimReviewPrompt())
        XCTAssertEqual(
            service.instrumentation,
            AppReviewInstrumentation(policyEvaluationCount: 2, promptClaimCount: 1)
        )
    }

    func testNewVersionWaitsFourteenDays() {
        let service = makeEligibleService()
        XCTAssertTrue(service.claimReviewPrompt())
        version = "1.2.4"

        advance(days: 13)
        XCTAssertFalse(service.claimReviewPrompt())
        advance(days: 1)
        XCTAssertTrue(service.claimReviewPrompt())
    }

    func testMissingVersionFailsClosed() {
        let service = makeEligibleService()
        version = nil
        XCTAssertFalse(service.claimReviewPrompt())
        XCTAssertNil(service.state.lastPromptDate)
        XCTAssertNil(service.state.lastPromptedVersion)
    }

    func testPricedIncomingBalanceIncreaseMustClearFiatFloor() {
        XCTAssertNotNil(
            AppReviewIncomingBalancePolicy.eventID(
                coinID: "btc-address",
                previousRawBalance: "100000000",
                currentRawBalance: "300000000",
                decimals: 8,
                fiatRate: 1,
                isNativeToken: true,
                minimumRawAmount: 100,
                isLikelySpam: false,
                baselineRefreshSucceeded: true,
                confirmationRefreshSucceeded: true
            )
        )
        XCTAssertNil(
            AppReviewIncomingBalancePolicy.eventID(
                coinID: "btc-address",
                previousRawBalance: "100000000",
                currentRawBalance: "150000000",
                decimals: 8,
                fiatRate: 1,
                isNativeToken: true,
                minimumRawAmount: 100,
                isLikelySpam: false,
                baselineRefreshSucceeded: true,
                confirmationRefreshSucceeded: true
            )
        )
    }

    func testUnpricedIncomingRequiresNativeAmountAboveDust() {
        XCTAssertEqual(
            AppReviewIncomingBalancePolicy.eventID(
                coinID: "native-address",
                previousRawBalance: "0",
                currentRawBalance: "100",
                decimals: 8,
                fiatRate: nil,
                isNativeToken: true,
                minimumRawAmount: 100,
                isLikelySpam: false,
                baselineRefreshSucceeded: true,
                confirmationRefreshSucceeded: true
            ),
            "native-address:100"
        )
        XCTAssertNil(
            AppReviewIncomingBalancePolicy.eventID(
                coinID: "token-address",
                previousRawBalance: "0",
                currentRawBalance: "1000000",
                decimals: 6,
                fiatRate: nil,
                isNativeToken: false,
                minimumRawAmount: 1,
                isLikelySpam: false,
                baselineRefreshSucceeded: true,
                confirmationRefreshSucceeded: true
            )
        )
    }

    func testIncomingRejectsSpamFailedRefreshAndInvalidBalances() {
        let validArguments = (
            coinID: "coin-address",
            previous: "0",
            current: "2000000"
        )

        XCTAssertNil(
            AppReviewIncomingBalancePolicy.eventID(
                coinID: validArguments.coinID,
                previousRawBalance: validArguments.previous,
                currentRawBalance: validArguments.current,
                decimals: 6,
                fiatRate: 1,
                isNativeToken: false,
                minimumRawAmount: 1,
                isLikelySpam: true,
                baselineRefreshSucceeded: true,
                confirmationRefreshSucceeded: true
            )
        )
        XCTAssertNil(
            AppReviewIncomingBalancePolicy.eventID(
                coinID: validArguments.coinID,
                previousRawBalance: validArguments.previous,
                currentRawBalance: validArguments.current,
                decimals: 6,
                fiatRate: 1,
                isNativeToken: false,
                minimumRawAmount: 1,
                isLikelySpam: false,
                baselineRefreshSucceeded: true,
                confirmationRefreshSucceeded: false
            )
        )
        XCTAssertNil(
            AppReviewIncomingBalancePolicy.eventID(
                coinID: validArguments.coinID,
                previousRawBalance: validArguments.previous,
                currentRawBalance: validArguments.current,
                decimals: 6,
                fiatRate: 1,
                isNativeToken: false,
                minimumRawAmount: 1,
                isLikelySpam: false,
                baselineRefreshSucceeded: false,
                confirmationRefreshSucceeded: true
            )
        )
        XCTAssertNil(
            AppReviewIncomingBalancePolicy.eventID(
                coinID: validArguments.coinID,
                previousRawBalance: "",
                currentRawBalance: validArguments.current,
                decimals: 6,
                fiatRate: 1,
                isNativeToken: false,
                minimumRawAmount: 1,
                isLikelySpam: false,
                baselineRefreshSucceeded: true,
                confirmationRefreshSucceeded: true
            )
        )
    }

    func testIncomingIgnoresBalanceAlreadyPresentAtLiveBaseline() {
        XCTAssertNil(
            AppReviewIncomingBalancePolicy.eventID(
                coinID: "coin-address",
                previousRawBalance: "2000000",
                currentRawBalance: "2000000",
                decimals: 6,
                fiatRate: 1,
                isNativeToken: false,
                minimumRawAmount: 1,
                isLikelySpam: false,
                baselineRefreshSucceeded: true,
                confirmationRefreshSucceeded: true
            )
        )
    }

    func testStateIsIsolatedPerDefaultsSuite() {
        let service = makeService()
        service.seedInstallDateIfNeeded()
        service.record(.vaultBackupCompleted(vaultID: "vault-a"))

        let otherSuiteName = "AppReviewServiceTests-other-\(UUID().uuidString)"
        let otherDefaults = UserDefaults(suiteName: otherSuiteName)!
        defer { otherDefaults.removePersistentDomain(forName: otherSuiteName) }
        let other = AppReviewService(
            defaults: otherDefaults,
            now: { [unowned self] in self.clock },
            bundleVersion: { "1.2.3" }
        )

        XCTAssertEqual(other.state.qualifyingEventCount, 0)
        XCTAssertNil(other.state.installDate)
    }
}
