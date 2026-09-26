#if os(iOS)
import XCTest
@testable import VultisigApp

@MainActor
final class TransactionLiveActivityCoordinatorTests: XCTestCase {
    private var client: ActivityClientSpy!
    private var defaults: UserDefaults!
    private var suite: String!
    private var rows: [UUID: TransactionHistoryData] = [:]
    private var hasVault = true
    private var lookupFails = false
    private var lookupFailureObserved: XCTestExpectation?
    private var vaultLookupFails = false
    private var resumedIDs: [UUID] = []

    override func setUp() async throws {
        try await super.setUp()
        client = ActivityClientSpy()
        suite = "live-activities-test-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        rows = [:]
        hasVault = true
        lookupFails = false
        lookupFailureObserved = nil
        vaultLookupFails = false
        resumedIDs = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try await super.tearDown()
    }

    private func coordinator(preparedImageKey: @escaping @MainActor (String) -> String? = { _ in nil },
                             prepareImage: @escaping @MainActor (URL) async -> Void = { _ in }) -> TransactionLiveActivityCoordinator {
        TransactionLiveActivityCoordinator(client: client, defaults: defaults,
                                           lookup: { [unowned self] in
                                               if self.lookupFails {
                                                   self.lookupFailureObserved?.fulfill()
                                                   throw NSError(domain: "fixture", code: 1)
                                               }
                                               return self.rows[$0]
                                           },
                                           vaultExists: { [unowned self] _ in
                                               if self.vaultLookupFails { throw NSError(domain: "fixture", code: 2) }
                                               return self.hasVault
                                           },
                                           resume: { [unowned self] in self.resumedIDs.append($0.id) },
                                           preparedImageKey: preparedImageKey, prepareImage: prepareImage)
    }

    private func addRow() -> TransactionHistoryData {
        let row = ActivityTestFixture.row()
        rows[row.id] = row
        return row
    }

    func testImagePreparationDoesNotBlockAdmissionOrStatusAndPreservesDelayedFreshness() async {
        let row = ActivityTestFixture.row(coinLogo: "https://example.com/coin.png")
        rows[row.id] = row
        let gate = ImagePreparationGate()
        let manager = coordinator(preparedImageKey: { _ in gate.key }, prepareImage: { _ in await gate.load() })
        manager.admit(row)
        XCTAssertEqual(client.requestCount, 1)
        XCTAssertNil(client.activities.first?.state.sourceImageKey)
        await fulfillment(of: [gate.started], timeout: 2)
        let observedAt = row.createdAt.addingTimeInterval(20)
        await manager.receive(.nativePending(row, observedAt))
        await manager.receive(.delayed(row))
        await manager.reconcile()
        XCTAssertEqual(gate.loads, 1)
        XCTAssertEqual(client.activities.first?.state.observedAt, observedAt)
        XCTAssertTrue(client.activities.first?.state.updateDelayed == true)
        rows[row.id] = ActivityTestFixture.row(id: row.id, hash: row.txHash, createdAt: row.createdAt,
            amountCrypto: "2 ETH", coinLogo: row.coinLogo)
        gate.complete()
        await fulfillment(of: [gate.finished], timeout: 2)
        await manager.waitForPendingUpdates()
        XCTAssertEqual(client.activities.first?.state.summary, "2 ETH")
        XCTAssertEqual(client.activities.first?.state.sourceImageKey, gate.key)
        XCTAssertEqual(client.activities.first?.state.observedAt, observedAt)
        XCTAssertTrue(client.activities.first?.state.updateDelayed == true)
        XCTAssertEqual(client.requestCount, 1)
    }

    func testAdmissionUsesPrewarmedImagesAndRenewsCacheProtectionOnce() async {
        let row = ActivityTestFixture.row(coinLogo: "https://example.com/coin.png")
        rows[row.id] = row
        let key = String(repeating: "a", count: 64)
        let renewed = expectation(description: "cached image retention renewed")
        var preparations = 0
        let manager = coordinator(preparedImageKey: { _ in key }, prepareImage: { _ in
            preparations += 1
            if preparations == 1 { renewed.fulfill() }
        })
        manager.admit(row)
        XCTAssertEqual(client.activities.first?.state.sourceImageKey, key)
        XCTAssertEqual(client.activities.first?.state.revision, 1)
        await fulfillment(of: [renewed], timeout: 2)
        await manager.waitForPendingUpdates()
        // The same key can now hold repaired bytes, requiring a new ActivityKit render.
        XCTAssertEqual(client.activities.first?.state.revision, 2)
        XCTAssertEqual(client.activities.first?.state.observedAt, row.createdAt)
        await manager.reconcile()
        await manager.waitForPendingUpdates()
        // Let a wrongly duplicated image task run before checking the attempt count.
        await Task.yield()
        XCTAssertEqual(preparations, 1)
    }

    func testImagePreparationRetriesAfterTemporaryStoreFailure() async {
        let row = ActivityTestFixture.row(coinLogo: "https://example.com/coin.png")
        rows[row.id] = row
        let gate = ImagePreparationGate()
        let manager = coordinator(preparedImageKey: { _ in gate.key }, prepareImage: { _ in await gate.load() })
        manager.admit(row)
        lookupFailureObserved = expectation(description: "temporary lookup failed")
        lookupFails = true
        await fulfillment(of: [lookupFailureObserved!], timeout: 2)
        lookupFailureObserved = nil
        lookupFails = false
        await manager.reconcile()
        await fulfillment(of: [gate.started], timeout: 2)
        gate.complete()
        await fulfillment(of: [gate.finished], timeout: 2)
        await manager.waitForPendingUpdates()
        XCTAssertEqual(client.activities.first?.state.sourceImageKey, gate.key)
        XCTAssertEqual(gate.loads, 1)
        XCTAssertEqual(client.requestCount, 1)
    }

    func testImageCompletionPreservesFreshSwapPhase() async {
        let row = ActivityTestFixture.row(type: .swap, coinLogo: "https://example.com/coin.png")
        rows[row.id] = row
        let gate = ImagePreparationGate()
        let manager = coordinator(preparedImageKey: { _ in gate.key }, prepareImage: { _ in await gate.load() })
        manager.admit(row)
        await fulfillment(of: [gate.started], timeout: 2)
        let updated = ActivityTestFixture.row(id: row.id, hash: row.txHash, type: .swap,
            createdAt: row.createdAt, coinLogo: row.coinLogo,
            tracking: .init(providerKind: "swapKit", latestTrackingStatus: "swapping"))
        rows[row.id] = updated
        let observedAt = row.createdAt.addingTimeInterval(20)
        await manager.receive(.swapStatus(updated, observedAt))
        XCTAssertEqual(client.activities.first?.state.phase, .swapping)
        gate.complete()
        await fulfillment(of: [gate.finished], timeout: 2)
        await manager.waitForPendingUpdates()
        XCTAssertEqual(client.activities.first?.state.phase, .swapping)
        XCTAssertEqual(client.activities.first?.state.observedAt, observedAt)
    }

    func testImageCompletionRevalidatesPrivacyWithoutReconcile() async {
        await assertUnreconciledImageCannotPublish(hideBalances: true)
    }

    func testImageCompletionRevalidatesDeletionWithoutReconcile() async {
        await assertUnreconciledImageCannotPublish(hideBalances: false)
    }

    private func assertUnreconciledImageCannotPublish(hideBalances: Bool) async {
        let row = ActivityTestFixture.row(coinLogo: "https://example.com/coin.png")
        rows[row.id] = row
        let gate = ImagePreparationGate()
        let manager = coordinator(preparedImageKey: { _ in gate.key }, prepareImage: { _ in await gate.load() })
        manager.admit(row)
        await fulfillment(of: [gate.started], timeout: 2)
        let previous = client.activities.first?.state
        if hideBalances { defaults.set(true, forKey: "showVaultBalance") } else { rows.removeValue(forKey: row.id) }
        gate.complete()
        await fulfillment(of: [gate.finished], timeout: 2)
        await manager.waitForPendingUpdates()
        XCTAssertFalse(gate.wasCancelled)
        XCTAssertEqual(client.activities.first?.state, previous)
        XCTAssertNil(client.activities.first?.state.sourceImageKey)
        XCTAssertEqual(client.requestCount, 1)
    }

    func testChangedImageURLCancelsOldJobAndOnlyPublishesCurrentResource() async {
        let oldURL = "https://example.com/old.png"
        let newURL = "https://example.com/new.png"
        let row = ActivityTestFixture.row(coinLogo: oldURL)
        rows[row.id] = row
        let oldImage = ImagePreparationGate()
        let newImage = ImagePreparationGate()
        let manager = coordinator(preparedImageKey: { $0 == oldURL ? oldImage.key : newImage.key },
            prepareImage: { await ($0.absoluteString == oldURL ? oldImage : newImage).load() })
        manager.admit(row)
        await fulfillment(of: [oldImage.started], timeout: 2)
        let replacement = ActivityTestFixture.row(id: row.id, hash: row.txHash,
            createdAt: row.createdAt, coinLogo: newURL)
        rows[row.id] = replacement
        await manager.receive(.saved(replacement))
        await fulfillment(of: [newImage.started], timeout: 2)
        oldImage.complete()
        await fulfillment(of: [oldImage.finished], timeout: 2)
        await manager.waitForPendingUpdates()
        XCTAssertTrue(oldImage.wasCancelled)
        XCTAssertNil(client.activities.first?.state.sourceImageKey)
        newImage.complete(key: String(repeating: "b", count: 64))
        await fulfillment(of: [newImage.finished], timeout: 2)
        await manager.waitForPendingUpdates()
        XCTAssertEqual(client.activities.first?.state.sourceImageKey, newImage.key)
        XCTAssertEqual(client.requestCount, 1)
        XCTAssertEqual(oldImage.loads, 1)
        XCTAssertEqual(newImage.loads, 1)
    }

    func testRejectedAndHiddenActivitiesDoNotPrepareImages() async {
        let row = ActivityTestFixture.row(coinLogo: "https://example.com/coin.png")
        rows[row.id] = row
        let manager = coordinator(prepareImage: { _ in XCTFail("Not accepted with visible details") })
        client.failRequest = true
        manager.admit(row)
        client.failRequest = false
        defaults.set(true, forKey: "showVaultBalance")
        let hidden = ActivityTestFixture.row(coinLogo: row.coinLogo)
        rows[hidden.id] = hidden
        manager.admit(hidden)
        await manager.reconcile()
        XCTAssertFalse(client.activities.first?.state.hasDetails ?? true)
    }

    func testLateImageAfterHidingBalancesIsCancelledAndCannotRevealDetails() async {
        await assertLateImageCannotPublish("privacy")
    }

    func testLateImageAfterDeletionCannotResurrectActivity() async { await assertLateImageCannotPublish("deletion") }
    func testLateImageAfterDismissalCannotResurrectActivity() async { await assertLateImageCannotPublish("dismissal") }
    func testLateImageAfterTerminalStatusCannotResurrectActivity() async { await assertLateImageCannotPublish("terminal") }
    func testLateImageAfterIdentityChangeCannotResurrectActivity() async { await assertLateImageCannotPublish("identity") }
    func testLateImageAfterExpiryCannotResurrectActivity() async { await assertLateImageCannotPublish("expiry") }
    func testLateImageAfterPermissionRevokedCannotResurrectActivity() async { await assertLateImageCannotPublish("permission") }

    private func assertLateImageCannotPublish(_ reason: String) async {
        let row = ActivityTestFixture.row(coinLogo: "https://example.com/coin.png")
        rows[row.id] = row
        let gate = ImagePreparationGate()
        let manager = coordinator(preparedImageKey: { _ in gate.key }, prepareImage: { _ in await gate.load() })
        manager.admit(row)
        await fulfillment(of: [gate.started], timeout: 2)
        switch reason {
        case "privacy": defaults.set(true, forKey: "showVaultBalance")
        case "deletion": rows.removeValue(forKey: row.id)
        case "dismissal": client.activities.removeAll()
        case "permission": client.isAuthorized = false
        case "identity":
            let replacement = ActivityTestFixture.row(id: row.id, coinLogo: row.coinLogo)
            rows[row.id] = replacement
            await manager.receive(.saved(replacement))
        case "terminal":
            let completed = ActivityTestFixture.row(id: row.id, hash: row.txHash, status: .successful,
                createdAt: row.createdAt, coinLogo: row.coinLogo)
            rows[row.id] = completed
            await manager.receive(.nativeStatus(completed, Date()))
        default: break
        }
        if reason != "identity" {
            await manager.reconcile(now: reason == "expiry" ? row.createdAt.addingTimeInterval(TransactionActivityPolicy.maximumAge + 1) : Date())
        }
        let stateBeforeCompletion = client.activities.first?.state
        gate.complete()
        await fulfillment(of: [gate.finished], timeout: 2)
        await manager.waitForPendingUpdates()
        XCTAssertTrue(gate.wasCancelled)
        XCTAssertEqual(client.activities.first?.state, stateBeforeCompletion)
        XCTAssertNil(client.activities.first?.state.sourceImageKey)
        XCTAssertEqual(client.requestCount, 1)
        if reason == "privacy" { XCTAssertFalse(client.activities.first?.state.hasDetails ?? true) }
    }

    func testReconcileDoesNotResumeARecordThatJustSettled() async {
        let row = addRow()
        let manager = coordinator()
        manager.admit(row)
        resumedIDs = []
        rows[row.id] = ActivityTestFixture.row(id: row.id, hash: row.txHash, status: .successful, createdAt: row.createdAt)
        await manager.reconcile()
        XCTAssertEqual(client.activities.first?.state.phase, .confirmed)
        XCTAssertTrue(resumedIDs.isEmpty)
    }

    func testLedgerPrunesExpiredDecisionsButKeepsRecentAndSystemRetainedEntries() throws {
        let expired = Date().addingTimeInterval(-TransactionActivityPolicy.maximumAge - 1)
        let old = addRow()
        let retained = addRow()
        let recent = addRow()
        let active = addRow()
        let state = TransactionActivityState(phase: .confirmed, observedAt: expired, revision: 1)
        client.activities = [.init(id: "retained", recordID: retained.id, state: state, isActive: false)]
        typealias Binding = TransactionLiveActivityCoordinator.Binding
        let ledger: [String: Binding] = [
            "old": .init(recordID: old.id, phase: .submitted, observedAt: expired, revision: 1, ended: true),
            "retained": .init(recordID: retained.id, phase: .confirmed, observedAt: expired, revision: 1, ended: true),
            "recent": .init(recordID: recent.id, phase: .submitted, observedAt: Date(), revision: 1, ended: true),
            "active": .init(recordID: active.id, phase: .pending, observedAt: expired, revision: 1, ended: false)
        ]
        defaults.set(try JSONEncoder().encode(ledger), forKey: TransactionActivityPolicy.ledgerKey)
        _ = coordinator()
        let stored = try XCTUnwrap(defaults.data(forKey: TransactionActivityPolicy.ledgerKey))
        let restored = try JSONDecoder().decode([String: Binding].self, from: stored)
        XCTAssertEqual(Set(restored.keys), ["retained", "recent", "active"])
    }

    func testBackgroundRefreshOnlyObservesRecognizedActiveRecords() async {
        let manager = coordinator()
        let first = addRow()
        let second = addRow()
        manager.admit(first)
        manager.admit(second)
        let third = addRow()
        manager.admit(third)
        client.activities.append(.init(id: "unrecognized", recordID: UUID(),
            state: .init(phase: .pending, observedAt: Date(), revision: 1), isActive: true))
        client.isForeground = false
        var observed = Set<UUID>()
        await manager.refreshInBackground { observed.insert($0.id) }
        XCTAssertEqual(observed, [first.id, second.id, third.id])
        XCTAssertEqual(client.requestCount, 3)
        client.activities = []
        await manager.refreshInBackground { _ in XCTFail("Dismissed activities must not fetch or restart") }
        XCTAssertFalse(manager.hasBackgroundWork)
        XCTAssertEqual(client.requestCount, 3)
    }

    func testBackgroundRefreshObservesMostStaleRecordsFirst() async {
        let manager = coordinator()
        let now = Date()
        let newest = ActivityTestFixture.row(createdAt: now)
        let middle = ActivityTestFixture.row(createdAt: now.addingTimeInterval(-30))
        let oldest = ActivityTestFixture.row(createdAt: now.addingTimeInterval(-90))
        for row in [newest, middle, oldest] { rows[row.id] = row }
        // Admit out of staleness order so a passing test proves reordering, not admission order.
        manager.admit(newest)
        manager.admit(middle)
        manager.admit(oldest)
        client.isForeground = false
        var observedOrder: [UUID] = []
        await manager.refreshInBackground { observedOrder.append($0.id) }
        XCTAssertEqual(observedOrder, [oldest.id, middle.id, newest.id])
    }

    func testBackgroundLookupFailsClosedForUnreadableOrMissingVault() {
        let row = addRow()
        let manager = coordinator()
        manager.admit(row)
        client.isForeground = false
        XCTAssertNotNil(manager.backgroundRecord(id: row.id))
        lookupFails = true
        XCTAssertNil(manager.backgroundRecord(id: row.id))
        lookupFails = false
        hasVault = false
        XCTAssertNil(manager.backgroundRecord(id: row.id))
        hasVault = true
        XCTAssertNil(manager.backgroundRecord(id: row.id, now: row.createdAt.addingTimeInterval(TransactionActivityPolicy.maximumAge)))
        client.isAuthorized = false
        XCTAssertNil(manager.backgroundRecord(id: row.id))
    }

    func testBackgroundRefreshWaitsForQueuedTerminalActivityWrite() async {
        let manager = coordinator()
        let row = addRow()
        manager.trackBroadcast(row)
        await manager.waitForPendingUpdates()
        client.isForeground = false
        await manager.refreshInBackground { _ in
            let updated = ActivityTestFixture.row(id: row.id, hash: row.txHash, status: .successful, createdAt: row.createdAt)
            self.rows[row.id] = updated
            NotificationCenter.default.post(name: TransactionHistoryActivityEvent.notification,
                                            object: TransactionHistoryActivityEvent.nativeStatus(updated, Date()))
        }
        XCTAssertEqual(client.activities.first?.state.phase, .confirmed)
        XCTAssertFalse(manager.hasBackgroundWork)
        XCTAssertEqual(client.requestCount, 1)
    }

    func testColdBackgroundRefreshSubscribesBeforePendingObservation() async {
        let row = addRow()
        coordinator().admit(row)
        let restored = coordinator()
        client.isForeground = false
        let observedAt = row.createdAt.addingTimeInterval(10)
        await restored.refreshInBackground { _ in
            NotificationCenter.default.post(name: TransactionHistoryActivityEvent.notification,
                                            object: TransactionHistoryActivityEvent.nativePending(row, observedAt))
        }
        XCTAssertEqual(client.activities.first?.state.observedAt, observedAt)
        XCTAssertEqual(client.requestCount, 1)
    }

    func testRestoreReplaysTerminalWriteInterruptedAfterLedgerPersistence() async {
        let row = addRow()
        let manager = coordinator()
        manager.admit(row)
        let before = client.activities
        let terminal = ActivityTestFixture.row(id: row.id, hash: row.txHash, status: .successful, createdAt: row.createdAt)
        rows[row.id] = terminal
        await manager.receive(.nativeStatus(terminal, Date()))
        client.activities = before // Simulate death before the system received end().
        await coordinator().reconcile()
        XCTAssertEqual(client.activities.first?.state.phase, .confirmed)
        XCTAssertEqual(client.activities.first?.isActive, false)
    }

    func testFreshInstallationStartsRichActivityWithoutOptIn() {
        let manager = coordinator()
        manager.admit(addRow())
        XCTAssertEqual(client.requestCount, 1)
        XCTAssertTrue(client.activities.first?.state.hasDetails ?? false)
    }

    func testHiddenBalancesStartPrivateWithoutPreviewPreferences() {
        defaults.set(true, forKey: "showVaultBalance")
        let manager = coordinator()
        manager.admit(addRow())
        XCTAssertEqual(client.requestCount, 1)
        XCTAssertFalse(client.activities.first?.state.hasDetails ?? true)
    }

    func testDuplicateAndRestorationDoNotRequestAgain() async {
        let row = addRow()
        let first = coordinator()
        first.admit(row)
        first.admit(row)
        let restored = coordinator()
        await restored.reconcile()
        restored.admit(row)
        XCTAssertEqual(client.requestCount, 1)
        XCTAssertEqual(client.activities.count, 1)
    }

    func testDismissalNeverResurrects() async {
        let row = addRow()
        let manager = coordinator()
        manager.admit(row)
        client.activities = []
        await manager.reconcile()
        manager.admit(row)
        let restored = coordinator()
        restored.admit(row)
        XCTAssertEqual(client.requestCount, 1)
    }

    func testAdmissionCoversEveryBroadcastOperation() {
        let manager = coordinator()
        for type in [TransactionHistoryType.send, .swap, .approve, .transaction, .limit, .trustLineActivation] {
            let row = ActivityTestFixture.row(type: type)
            rows[row.id] = row
            manager.admit(row)
        }
        XCTAssertEqual(client.requestCount, 6)
        XCTAssertEqual(Set(client.activities.compactMap { $0.state.operation?.rawValue }),
                       Set(["send", "swap", "approval", "limit", "transaction"]))
    }

    func testEveryBroadcastIsOfferedToSystemCapacityWithoutResurrectingDismissals() async {
        let manager = coordinator()
        manager.admit(addRow())
        manager.admit(addRow())
        let overflow = addRow()
        manager.admit(overflow)
        client.activities = []
        await manager.reconcile()
        manager.admit(overflow)
        XCTAssertEqual(client.requestCount, 3)
    }

    func testPrivateModeRedactsRunningAndRetainedTerminalContent() async {
        let manager = coordinator()
        let row = addRow()
        manager.admit(row)
        XCTAssertNotNil(client.activities.first?.state.summary)
        defaults.set(true, forKey: "showVaultBalance")
        await manager.reconcile()
        XCTAssertNil(client.activities.first?.state.summary)
        defaults.set(false, forKey: "showVaultBalance")
        await manager.reconcile()
        let completed = ActivityTestFixture.row(id: row.id, hash: row.txHash, status: .successful, createdAt: row.createdAt)
        rows[row.id] = completed
        await manager.receive(.nativeStatus(completed, Date()))
        XCTAssertFalse(client.activities.first?.isActive ?? true)
        XCTAssertNotNil(client.activities.first?.state.summary)
        let endsBeforeOrdinaryRefresh = client.immediateEnds.count
        await manager.reconcile()
        XCTAssertEqual(client.immediateEnds.count, endsBeforeOrdinaryRefresh)
        XCTAssertEqual(client.activities.first?.state.phase, .confirmed)
        XCTAssertNotNil(client.activities.first?.state.summary)
        defaults.set(true, forKey: "showVaultBalance")
        await manager.reconcile()
        XCTAssertTrue(client.immediateEnds.last ?? false)
        XCTAssertNil(client.activities.first?.state.summary)
    }

    func testRevocationDeletionAndVaultDeletionEndWithoutResurrection() async {
        for change in 0..<3 {
            let row = addRow()
            client.isAuthorized = true
            hasVault = true
            let manager = coordinator()
            manager.admit(row)
            if change == 0 { client.isAuthorized = false }
            if change == 1 { rows.removeValue(forKey: row.id) }
            if change == 2 { hasVault = false }
            await manager.reconcile()
            XCTAssertTrue(client.immediateEnds.last ?? false)
            let count = client.requestCount
            manager.admit(row)
            XCTAssertEqual(client.requestCount, count)
        }
    }

    func testRetainedReceiptsAreRemovedOnDeletionVaultDeletionAndRevocation() async {
        for change in 0..<3 {
            client.activities = []
            hasVault = true
            client.isAuthorized = true
            let row = addRow()
            let manager = coordinator()
            manager.admit(row)
            let completed = ActivityTestFixture.row(id: row.id, hash: row.txHash, status: .successful, createdAt: row.createdAt)
            rows[row.id] = completed
            await manager.receive(.nativeStatus(completed, Date()))
            let activityID = client.activities.first(where: { $0.recordID == row.id })!.id
            XCTAssertFalse(client.activities.first(where: { $0.id == activityID })!.isActive)
            let priorEnds = client.immediateEnds.count
            await manager.reconcile()
            XCTAssertEqual(client.immediateEnds.count, priorEnds)
            if change == 0 { client.isAuthorized = false }
            if change == 1 { rows.removeValue(forKey: row.id) }
            if change == 2 { hasVault = false }
            await manager.reconcile()
            XCTAssertTrue(client.immediateEnds.last ?? false)
            XCTAssertFalse(client.activities.first(where: { $0.id == activityID })!.state.hasDetails)
        }
    }

    func testTransientRecordAndVaultLookupErrorsPreserveActivity() async {
        let manager = coordinator()
        let row = addRow()
        manager.admit(row)
        lookupFails = true
        await manager.reconcile()
        XCTAssertTrue(client.activities.first?.isActive ?? false)
        lookupFails = false
        vaultLookupFails = true
        await manager.reconcile()
        await manager.receive(.nativeStatus(row, Date()))
        XCTAssertTrue(client.activities.first?.isActive ?? false)
        XCTAssertTrue(client.immediateEnds.isEmpty)
    }

    func testPrivacyRedactsBeforeEitherStoreLookupCanFail() async {
        for failVault in [false, true] {
            lookupFails = false
            vaultLookupFails = false
            defaults.set(false, forKey: "showVaultBalance")
            let row = addRow()
            let manager = coordinator()
            manager.admit(row)
            let initial = client.activities.first(where: { $0.recordID == row.id })!.state
            XCTAssertTrue(initial.hasDetails)
            lookupFails = !failVault
            vaultLookupFails = failVault
            defaults.set(true, forKey: "showVaultBalance")
            await manager.reconcile()
            let redacted = client.activities.first(where: { $0.recordID == row.id })!.state
            XCTAssertFalse(redacted.hasDetails)
            XCTAssertEqual(redacted.phase, initial.phase)
            XCTAssertEqual(redacted.observedAt, initial.observedAt)
        }
    }

    func testRestoreUsesDurableTerminalEvidenceEvenAfterDelayedActivity() async {
        let row = addRow()
        let manager = coordinator()
        manager.admit(row)
        await manager.receive(.delayed(row))
        let completed = ActivityTestFixture.row(id: row.id, hash: row.txHash, status: .successful, createdAt: row.createdAt)
        rows[row.id] = completed
        let restored = coordinator()
        await restored.reconcile()
        XCTAssertEqual(client.activities.first?.state.phase, .confirmed)
        XCTAssertEqual(client.activities.first?.state.observedAt, completed.completedAt)
    }

    func testFailedRequestsAndDeniedPermissionNeverAutoRetry() {
        let row = addRow()
        let manager = coordinator()
        client.failRequest = true
        manager.admit(row)
        client.failRequest = false
        manager.admit(row)
        XCTAssertEqual(client.requestCount, 1)
        let denied = addRow()
        client.isAuthorized = false
        manager.admit(denied)
        client.isAuthorized = true
        manager.admit(denied)
        XCTAssertEqual(client.requestCount, 1)
    }

    func testSavedAndReconciledRowsDoNotInventFreshness() async {
        let row = addRow()
        let manager = coordinator()
        manager.admit(row)
        await manager.receive(.saved(row))
        await manager.reconcile()
        XCTAssertEqual(client.activities.first?.state.observedAt, row.createdAt)
        let fresh = row.createdAt.addingTimeInterval(20)
        await manager.receive(.nativeStatus(row, fresh))
        XCTAssertEqual(client.activities.first?.state.observedAt, fresh)
        await manager.receive(.delayed(row))
        XCTAssertEqual(client.activities.first?.state.observedAt, fresh)
        XCTAssertTrue(client.activities.first?.state.updateDelayed ?? false)
        await manager.receive(.saved(row))
        XCTAssertTrue(client.activities.first?.state.updateDelayed ?? false)
        await manager.receive(.nativeStatus(row, row.createdAt))
        XCTAssertEqual(client.activities.first?.state.observedAt, fresh)
    }

    func testNativeSwapRevertIsFailureButPendingAfterProviderErrorIsNot() async {
        let row = ActivityTestFixture.row(type: .swap)
        rows[row.id] = row
        let manager = coordinator()
        manager.admit(row)
        let providerError = ActivityTestFixture.row(id: row.id, hash: row.txHash, type: .swap, status: .error,
                                                    createdAt: row.createdAt,
                                                    tracking: .init(providerKind: "swapKit", latestTrackingStatus: "parsing_error"))
        rows[row.id] = providerError
        await manager.receive(.swapStatus(providerError, Date()))
        await manager.receive(.nativePending(providerError, Date()))
        XCTAssertFalse(client.activities.first?.state.phase.isTerminal ?? true)
        let reverted = ActivityTestFixture.row(id: row.id, hash: row.txHash, type: .swap, status: .error,
                                               createdAt: row.createdAt, error: "reverted")
        rows[row.id] = reverted
        await manager.receive(.nativeStatus(reverted, Date()))
        XCTAssertEqual(client.activities.first?.state.phase, .failed)
    }

    func testTerminalDoesNotRegressAndLifetimeEndsHonestly() async {
        let row = addRow()
        let manager = coordinator()
        manager.admit(row)
        let completed = ActivityTestFixture.row(id: row.id, hash: row.txHash, status: .successful, createdAt: row.createdAt)
        await manager.receive(.nativeStatus(completed, Date()))
        await manager.receive(.nativeStatus(row, Date()))
        XCTAssertEqual(client.activities.first?.state.phase, .confirmed)
        let second = addRow()
        manager.admit(second)
        await manager.reconcile(now: second.createdAt.addingTimeInterval(TransactionActivityPolicy.maximumAge + 1))
        XCTAssertEqual(client.activities.last?.state.phase, .trackingEnded)
    }
}

@MainActor
private final class ImagePreparationGate {
    let started = XCTestExpectation(description: "image preparation started")
    let finished = XCTestExpectation(description: "image preparation returned")
    var key: String?
    var loads = 0
    var wasCancelled = false
    private var continuation: CheckedContinuation<Void, Never>?

    func load() async {
        loads += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
        wasCancelled = Task.isCancelled
        finished.fulfill()
    }

    func complete(key: String = String(repeating: "a", count: 64)) {
        self.key = key
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class ActivityClientSpy: TransactionActivityClient {
    var isAuthorized = true
    var isForeground = true
    var activities: [TransactionActivityHandle] = []
    var requestCount = 0
    var failRequest = false
    var immediateEnds: [Bool] = []

    func request(recordID: UUID, state: TransactionActivityState) throws -> String {
        requestCount += 1
        if failRequest { throw NSError(domain: "fixture", code: 1) }
        let id = UUID().uuidString
        activities.append(TransactionActivityHandle(id: id, recordID: recordID, state: state, isActive: true))
        return id
    }

    func update(id: String, state: TransactionActivityState) {
        replace(id: id, state: state, active: true)
    }

    func end(id: String, state: TransactionActivityState, immediately: Bool) {
        immediateEnds.append(immediately)
        replace(id: id, state: state, active: false)
    }

    private func replace(id: String, state: TransactionActivityState, active: Bool) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[index] = TransactionActivityHandle(id: id, recordID: activities[index].recordID, state: state, isActive: active)
    }
}
#endif
