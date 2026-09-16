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

    private var store: TestContextToken?

    override func setUp() async throws {
        store = try TestStore.installInMemoryContainer()
    }

    override func tearDown() async throws {
        TestStore.restore(store)
        store = nil
    }

    private func makeVault() -> Vault {
        let vault = TestStore.makeVault(pubKey: UUID().uuidString)
        vault.localPartyID = "device"
        vault.signers = ["device", "server-fixture"]
        return vault
    }

    func testUnknownPreservesConfirmationAndRetriesWhileFresh() async {
        let vault = makeVault()
        let confirmedAt = Date()
        vault.fastVaultEligibility = true
        vault.fastVaultEligibilityCheckedAt = confirmedAt
        var calls = 0
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in calls += 1; return .unknown(.requestFailed) },
            saveStorage: { XCTFail("Unknown must not save confirmation") }
        )
        await refresher.refresh(vault)
        await refresher.refreshIfStale(vault)
        XCTAssertEqual(calls, 2)
        XCTAssertTrue(vault.fastVaultEligibility)
        XCTAssertEqual(vault.fastVaultEligibilityCheckedAt, confirmedAt)
        XCTAssertTrue(vault.offersFastSigning)
    }

    func testColdStructuralIdentityAndServerLocalExclusion() {
        let vault = makeVault()
        XCTAssertTrue(vault.offersFastSigning)
        vault.localPartyID = "SERVER-fixture"
        XCTAssertFalse(vault.offersFastSigning)
        vault.localPartyID = "device"
        vault.signers = ["device", "other"]
        XCTAssertFalse(vault.offersFastSigning)
    }

    // MARK: - refresh

    func testRefreshUpdatesCacheAndTimestamp() async {
        let vault = makeVault()
        XCTAssertFalse(vault.fastVaultEligibility)
        XCTAssertNil(vault.fastVaultEligibilityCheckedAt)

        let fixedDate = Date(timeIntervalSince1970: 1_000_000)
        var saveCalls = 0
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in .present },
            saveStorage: { saveCalls += 1 },
            now: { fixedDate }
        )

        await refresher.refresh(vault)

        XCTAssertTrue(vault.fastVaultEligibility)
        XCTAssertEqual(vault.fastVaultEligibilityCheckedAt, fixedDate)
        XCTAssertEqual(saveCalls, 1)
    }

    func testRefreshCanFlipFromTrueToFalse() async {
        let vault = makeVault()
        vault.fastVaultEligibility = true
        vault.fastVaultEligibilityCheckedAt = Date(timeIntervalSince1970: 0)

        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in .absent },
            saveStorage: { },
            now: { Date(timeIntervalSince1970: 100) }
        )

        await refresher.refresh(vault)

        XCTAssertFalse(vault.fastVaultEligibility)
        XCTAssertEqual(vault.fastVaultEligibilityCheckedAt, Date(timeIntervalSince1970: 100))
    }

    func testRefreshPassesVaultToCheckClosure() async {
        let vault = makeVault()
        vault.pubKeyECDSA = "specific-pubkey"

        var receivedVault: Vault?
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { v in
                receivedVault = v
                return .present
            },
            saveStorage: { },
            now: { Date() }
        )

        await refresher.refresh(vault)

        XCTAssertIdentical(receivedVault, vault)
    }

    // MARK: - refreshIfStale

    func testRefreshIfStaleRunsWhenNeverChecked() async {
        let vault = makeVault()
        XCTAssertNil(vault.fastVaultEligibilityCheckedAt)

        var checkCalls = 0
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in checkCalls += 1; return .present },
            saveStorage: { },
            now: { Date() }
        )

        await refresher.refreshIfStale(vault)
        XCTAssertEqual(checkCalls, 1)
        XCTAssertTrue(vault.fastVaultEligibility)
    }

    func testRefreshIfStaleSkipsWhenWithinThreshold() async {
        let vault = makeVault()
        let lastCheck = Date(timeIntervalSince1970: 1_000_000)
        vault.fastVaultEligibility = true
        vault.fastVaultEligibilityCheckedAt = lastCheck

        var checkCalls = 0
        // Threshold = 24h; now = lastCheck + 1h → within threshold
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in checkCalls += 1; return .absent },
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
        let vault = makeVault()
        let lastCheck = Date(timeIntervalSince1970: 1_000_000)
        vault.fastVaultEligibility = false
        vault.fastVaultEligibilityCheckedAt = lastCheck

        var checkCalls = 0
        // Threshold = 24h; now = lastCheck + 25h → expired
        let now = lastCheck.addingTimeInterval(25 * 60 * 60)
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in checkCalls += 1; return .present },
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
        let vault = makeVault()
        let lastCheck = Date(timeIntervalSince1970: 1_000_000)
        vault.fastVaultEligibilityCheckedAt = lastCheck

        var checkCalls = 0
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in checkCalls += 1; return .present },
            saveStorage: { },
            now: { lastCheck.addingTimeInterval(24 * 60 * 60) },  // exactly at threshold
            stalenessThreshold: 24 * 60 * 60
        )

        await refresher.refreshIfStale(vault)

        XCTAssertEqual(checkCalls, 1)
    }

    func testConcurrentRequestsCoalesce() async {
        let vault = makeVault()
        var calls = 0
        var release: CheckedContinuation<FastVaultPresence, Never>?
        let started = expectation(description: "lookup starts")
        let joined = expectation(description: "second consumer joins")
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in
                calls += 1
                return await withCheckedContinuation { release = $0; started.fulfill() }
            }, saveStorage: {}
        )
        let first = Task { await refresher.resolvePresence(vault) }
        await fulfillment(of: [started], timeout: 2)
        let second = Task {
            joined.fulfill()
            return await refresher.resolvePresence(vault)
        }
        await fulfillment(of: [joined], timeout: 2)
        release?.resume(returning: .present)
        let results = await [first.value, second.value]
        XCTAssertEqual(results, [.present, .present])
        XCTAssertEqual(calls, 1)
    }

    func testLateResponseCannotChangeNewTopology() async {
        let vault = makeVault()
        var release: CheckedContinuation<FastVaultPresence, Never>?
        let started = expectation(description: "lookup starts")
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in
                await withCheckedContinuation { release = $0; started.fulfill() }
            }, saveStorage: { XCTFail("Stale topology cannot save") }
        )
        let task = Task { await refresher.resolvePresence(vault) }
        await fulfillment(of: [started], timeout: 2)
        vault.signers = ["device", "server-replacement"]
        release?.resume(returning: .absent)
        let result = await task.value
        XCTAssertTrue(result.isUnknown)
        XCTAssertNil(vault.fastVaultEligibilityCheckedAt)
        XCTAssertTrue(vault.offersFastSigning)
    }

    func testCancelledCallerStillLetsLookupPopulateCache() async {
        let vault = makeVault()
        vault.fastVaultEligibility = true
        vault.fastVaultEligibilityCheckedAt = Date()
        var release: CheckedContinuation<FastVaultPresence, Never>?
        var calls = 0
        let started = expectation(description: "lookup starts")
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in
                calls += 1
                if calls > 1 { return .present }
                return await withCheckedContinuation { release = $0; started.fulfill() }
            }, saveStorage: {}
        )
        let task = Task { await refresher.resolvePresence(vault) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await Task.yield()
        release?.resume(returning: .present)
        let result = await task.value
        XCTAssertEqual(result, .unknown(.cancelled))
        XCTAssertEqual(vault.fastVaultPresenceOutcome, .present)
        XCTAssertEqual(refresher.confirmedPresenceForRouting(vault), .present)
        await refresher.refreshIfStale(vault)
        XCTAssertEqual(calls, 1)
    }

    func testDeletedVaultIgnoresLateResponse() async throws {
        let vault = makeVault()
        var release: CheckedContinuation<FastVaultPresence, Never>?
        let started = expectation(description: "lookup starts")
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in
                await withCheckedContinuation { release = $0; started.fulfill() }
            }, saveStorage: { XCTFail("Deleted vault cannot save") }
        )
        let task = Task { await refresher.resolvePresence(vault) }
        await fulfillment(of: [started], timeout: 2)
        let context = Storage.shared.modelContext!
        context.delete(vault)
        try context.save()
        release?.resume(returning: .present)
        let result = await task.value
        XCTAssertTrue(result.isUnknown)
        XCTAssertFalse(context.fetchAllVaults().contains(where: { $0 === vault }))
    }

    func testChangedTopologyDiscardsPriorAbsenceForPresentationAndTTL() async {
        let vault = makeVault()
        var calls = 0
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in
                calls += 1
                return calls == 1 ? .absent : .unknown(.requestFailed)
            }, saveStorage: {}
        )
        await refresher.refresh(vault)
        XCTAssertFalse(vault.offersFastSigning)
        vault.signers = ["device", "server-new"]
        XCTAssertTrue(vault.offersFastSigning)
        await refresher.refreshIfStale(vault)
        XCTAssertEqual(calls, 2)
        XCTAssertTrue(vault.offersFastSigning)
        XCTAssertFalse(vault.isFastVault)
    }

    func testChangedTopologyDoesNotInheritConfirmedPresence() async {
        let vault = makeVault()
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in .present }, saveStorage: {}
        )
        await refresher.refresh(vault)
        XCTAssertTrue(vault.isFastVault)
        vault.pubKeyECDSA = "replacement-\(UUID().uuidString)"
        XCTAssertFalse(vault.isFastVault)
        XCTAssertTrue(vault.offersFastSigning)
    }

    func testNewServerSignerDoesNotInheritSecureTopologyConfirmation() async {
        let vault = makeVault()
        vault.signers = ["device", "other-device"]
        vault.fastVaultEligibility = false
        vault.fastVaultEligibilityCheckedAt = Date()
        vault.fastVaultCheckedTopology = FastVaultTopology(vault)
        vault.signers = ["device", "server-new"]
        var calls = 0
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in calls += 1; return .unknown(.requestFailed) },
            saveStorage: {}
        )
        await refresher.refreshIfStale(vault)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(vault.offersFastSigning)
    }

    func testActionTimeLookupDoesNotTrustFreshConfirmation() async {
        let vault = makeVault()
        vault.fastVaultEligibility = true
        vault.fastVaultEligibilityCheckedAt = Date()
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in .unknown(.requestFailed) }, saveStorage: {}
        )
        let result = await refresher.resolvePresence(vault)
        XCTAssertEqual(result, .unknown(.requestFailed))
        XCTAssertTrue(vault.offersFastSigning)
    }

    func testCancellingOneConsumerPreservesOtherConsumer() async {
        let vault = makeVault()
        var release: CheckedContinuation<FastVaultPresence, Never>?
        var calls = 0
        let started = expectation(description: "lookup starts")
        let joined = expectation(description: "second consumer joins")
        let refresher = FastVaultEligibilityRefresher(checkEligibility: { _ in
            calls += 1
            return await withCheckedContinuation { release = $0; started.fulfill() }
        }, saveStorage: {})
        let first = Task { await refresher.resolvePresence(vault) }
        await fulfillment(of: [started], timeout: 2)
        let second = Task {
            joined.fulfill()
            return await refresher.resolvePresence(vault)
        }
        await fulfillment(of: [joined], timeout: 2)
        first.cancel()
        await Task.yield()
        release?.resume(returning: .present)
        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertEqual(firstResult, .unknown(.cancelled))
        XCTAssertEqual(secondResult, .present)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(vault.fastVaultPresenceOutcome, .present)
    }

    func testReplacementLookupSurvivesOldTopologyCompletion() async {
        let vault = makeVault()
        var releases: [CheckedContinuation<FastVaultPresence, Never>] = []
        let firstStarted = expectation(description: "original topology starts")
        let replacementStarted = expectation(description: "replacement topology starts")
        var calls = 0
        let refresher = FastVaultEligibilityRefresher(checkEligibility: { _ in
            calls += 1
            return await withCheckedContinuation { continuation in
                releases.append(continuation)
                if calls == 1 { firstStarted.fulfill() } else { replacementStarted.fulfill() }
            }
        }, saveStorage: {})
        let first = Task { await refresher.resolvePresence(vault) }
        await fulfillment(of: [firstStarted], timeout: 2)
        vault.signers = ["device", "server-replacement"]
        let replacement = Task { await refresher.resolvePresence(vault) }
        await fulfillment(of: [replacementStarted], timeout: 2)
        releases[0].resume(returning: .absent)
        let discarded = await first.value
        XCTAssertTrue(discarded.isUnknown)
        let joined = expectation(description: "caller joins replacement")
        let consumer = Task {
            joined.fulfill()
            return await refresher.resolvePresence(vault)
        }
        await fulfillment(of: [joined], timeout: 2)
        releases[1].resume(returning: .present)
        let results = await [replacement.value, consumer.value]
        XCTAssertEqual(results, [.present, .present])
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(vault.fastVaultCheckedTopology, FastVaultTopology(vault))
    }

}
