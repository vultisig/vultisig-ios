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
    private var vaultLookupFails = false

    override func setUp() async throws {
        try await super.setUp()
        client = ActivityClientSpy()
        suite = "live-activities-test-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: TransactionActivityPolicy.enabledKey)
        defaults.set(true, forKey: TransactionActivityPolicy.detailsKey)
        rows = [:]
        hasVault = true
        lookupFails = false
        vaultLookupFails = false
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try await super.tearDown()
    }

    private func coordinator() -> TransactionLiveActivityCoordinator {
        TransactionLiveActivityCoordinator(client: client, defaults: defaults,
                                           lookup: { [unowned self] in
                                               if self.lookupFails { throw NSError(domain: "fixture", code: 1) }
                                               return self.rows[$0]
                                           },
                                           vaultExists: { [unowned self] _ in
                                               if self.vaultLookupFails { throw NSError(domain: "fixture", code: 2) }
                                               return self.hasVault
                                           },
                                           featureEnabled: true, resume: { _ in })
    }

    private func addRow() -> TransactionHistoryData {
        let row = ActivityTestFixture.row()
        rows[row.id] = row
        return row
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

    func testTwoActivityCapDoesNotAutoPromoteOverflow() async {
        let manager = coordinator()
        manager.admit(addRow())
        manager.admit(addRow())
        let overflow = addRow()
        manager.admit(overflow)
        client.activities = []
        await manager.reconcile()
        manager.admit(overflow)
        XCTAssertEqual(client.requestCount, 2)
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
        defaults.set(false, forKey: TransactionActivityPolicy.detailsKey)
        await manager.reconcile()
        XCTAssertTrue(client.immediateEnds.last ?? false)
        XCTAssertNil(client.activities.first?.state.summary)
    }

    func testDisablingDeletionAndVaultDeletionEndWithoutResurrection() async {
        for change in 0..<3 {
            let row = addRow()
            defaults.set(true, forKey: TransactionActivityPolicy.enabledKey)
            hasVault = true
            let manager = coordinator()
            manager.admit(row)
            if change == 0 { defaults.set(false, forKey: TransactionActivityPolicy.enabledKey) }
            if change == 1 { rows.removeValue(forKey: row.id) }
            if change == 2 { hasVault = false }
            await manager.reconcile()
            XCTAssertTrue(client.immediateEnds.last ?? false)
            let count = client.requestCount
            manager.admit(row)
            XCTAssertEqual(client.requestCount, count)
        }
    }

    func testRetainedReceiptsAreRemovedOnDisableDeletionVaultDeletionAndRevocation() async {
        for change in 0..<4 {
            client.activities = []
            defaults.set(true, forKey: TransactionActivityPolicy.enabledKey)
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
            if change == 0 { defaults.set(false, forKey: TransactionActivityPolicy.enabledKey) }
            if change == 1 { rows.removeValue(forKey: row.id) }
            if change == 2 { hasVault = false }
            if change == 3 { client.isAuthorized = false }
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
