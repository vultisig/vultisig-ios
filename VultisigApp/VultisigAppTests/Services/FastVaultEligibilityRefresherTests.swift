//
//  FastVaultEligibilityRefresherTests.swift
//  VultisigAppTests
//
//  Unit tests for the fast-vault eligibility cache refresher. Closure-injected
//  dependencies (`checkEligibility`, `saveStorage`, `now`) keep tests fully
//  offline.
//

import XCTest
@testable import VultisigApp

@MainActor
final class FastVaultEligibilityRefresherTests: XCTestCase {

    // MARK: - refresh

    func testRefreshUpdatesCacheAndTimestamp() async {
        let vault = SendFormFixture.makeVault()
        XCTAssertFalse(vault.fastVaultEligibility)
        XCTAssertNil(vault.fastVaultEligibilityCheckedAt)

        let fixedDate = Date(timeIntervalSince1970: 1_000_000)
        var saveCalls = 0
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in true },
            saveStorage: { saveCalls += 1 },
            now: { fixedDate }
        )

        await refresher.refresh(vault)

        XCTAssertTrue(vault.fastVaultEligibility)
        XCTAssertEqual(vault.fastVaultEligibilityCheckedAt, fixedDate)
        XCTAssertEqual(saveCalls, 1)
    }

    func testRefreshCanFlipFromTrueToFalse() async {
        let vault = SendFormFixture.makeVault()
        vault.fastVaultEligibility = true
        vault.fastVaultEligibilityCheckedAt = Date(timeIntervalSince1970: 0)

        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in false },
            saveStorage: { },
            now: { Date(timeIntervalSince1970: 100) }
        )

        await refresher.refresh(vault)

        XCTAssertFalse(vault.fastVaultEligibility)
        XCTAssertEqual(vault.fastVaultEligibilityCheckedAt, Date(timeIntervalSince1970: 100))
    }

    func testRefreshPassesVaultToCheckClosure() async {
        let vault = SendFormFixture.makeVault()
        vault.pubKeyECDSA = "specific-pubkey"

        var receivedVault: Vault?
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { v in
                receivedVault = v
                return true
            },
            saveStorage: { },
            now: { Date() }
        )

        await refresher.refresh(vault)

        XCTAssertIdentical(receivedVault, vault)
    }

    // MARK: - refreshIfStale

    func testRefreshIfStaleRunsWhenNeverChecked() async {
        let vault = SendFormFixture.makeVault()
        XCTAssertNil(vault.fastVaultEligibilityCheckedAt)

        var checkCalls = 0
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in checkCalls += 1; return true },
            saveStorage: { },
            now: { Date() }
        )

        await refresher.refreshIfStale(vault)
        XCTAssertEqual(checkCalls, 1)
        XCTAssertTrue(vault.fastVaultEligibility)
    }

    func testRefreshIfStaleSkipsWhenWithinThreshold() async {
        let vault = SendFormFixture.makeVault()
        let lastCheck = Date(timeIntervalSince1970: 1_000_000)
        vault.fastVaultEligibility = true
        vault.fastVaultEligibilityCheckedAt = lastCheck

        var checkCalls = 0
        // Threshold = 24h; now = lastCheck + 1h → within threshold
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in checkCalls += 1; return false },
            saveStorage: { },
            now: { lastCheck.addingTimeInterval(60 * 60) },
            stalenessThreshold: 24 * 60 * 60
        )

        await refresher.refreshIfStale(vault)

        XCTAssertEqual(checkCalls, 0)
        XCTAssertTrue(vault.fastVaultEligibility, "cached value preserved")
        XCTAssertEqual(vault.fastVaultEligibilityCheckedAt, lastCheck, "timestamp untouched")
    }

    func testRefreshIfStaleRunsWhenExpired() async {
        let vault = SendFormFixture.makeVault()
        let lastCheck = Date(timeIntervalSince1970: 1_000_000)
        vault.fastVaultEligibility = false
        vault.fastVaultEligibilityCheckedAt = lastCheck

        var checkCalls = 0
        // Threshold = 24h; now = lastCheck + 25h → expired
        let now = lastCheck.addingTimeInterval(25 * 60 * 60)
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in checkCalls += 1; return true },
            saveStorage: { },
            now: { now },
            stalenessThreshold: 24 * 60 * 60
        )

        await refresher.refreshIfStale(vault)

        XCTAssertEqual(checkCalls, 1)
        XCTAssertTrue(vault.fastVaultEligibility)
        XCTAssertEqual(vault.fastVaultEligibilityCheckedAt, now)
    }

    func testRefreshIfStaleRunsAtExactThresholdBoundary() async {
        // At exactly `stalenessThreshold` elapsed, treat as stale (>=).
        let vault = SendFormFixture.makeVault()
        let lastCheck = Date(timeIntervalSince1970: 1_000_000)
        vault.fastVaultEligibilityCheckedAt = lastCheck

        var checkCalls = 0
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in checkCalls += 1; return true },
            saveStorage: { },
            now: { lastCheck.addingTimeInterval(24 * 60 * 60) },  // exactly at threshold
            stalenessThreshold: 24 * 60 * 60
        )

        await refresher.refreshIfStale(vault)

        XCTAssertEqual(checkCalls, 1)
    }
}
