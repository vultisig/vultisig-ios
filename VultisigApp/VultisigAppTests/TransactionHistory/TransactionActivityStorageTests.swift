import Combine
import SwiftData
import XCTest
@testable import VultisigApp

@MainActor
final class TransactionActivityStorageTests: XCTestCase {
    private func container() throws -> ModelContainer {
        let schema = Schema([TransactionHistoryItem.self, SwapTrackingMetadata.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    func testBroadcastReceiptIsEnrichedWithoutReplacingOutcomeOrIdentity() throws {
        let container = try container()
        let storage = TransactionHistoryStorage(modelContext: container.mainContext)
        let broadcast = ActivityTestFixture.row(amountFiat: "")
        try storage.save(broadcast)
        try storage.updateStatus(txHash: broadcast.txHash, pubKeyECDSA: broadcast.pubKeyECDSA, status: .successful)
        let done = ActivityTestFixture.row(hash: broadcast.txHash, createdAt: broadcast.createdAt,
                                           amountCrypto: "2 ETH", amountFiat: "5000", fee: "0.001 ETH")
        try storage.save(done)
        let row = try XCTUnwrap(storage.fetch(id: broadcast.id))
        XCTAssertEqual(row.amountCrypto, broadcast.amountCrypto)
        XCTAssertEqual(row.amountFiat, done.amountFiat)
        XCTAssertEqual(row.feeCrypto, done.feeCrypto)
        XCTAssertEqual(row.status, .successful)
        XCTAssertEqual(row.id, broadcast.id)
        XCTAssertEqual(try storage.fetchAll(pubKeyECDSA: row.pubKeyECDSA).count, 1)
        try storage.save(ActivityTestFixture.row(hash: broadcast.txHash, fee: "9 ETH"))
        XCTAssertEqual(try storage.fetch(id: broadcast.id)?.feeCrypto, "0.001 ETH")
    }

    func testLateDoneTrackingIdentifiersPreserveObservedSettlement() throws {
        let container = try container()
        let storage = TransactionHistoryStorage(modelContext: container.mainContext)
        let row = ActivityTestFixture.row(type: .swap, tracking: .init(providerKind: "swapKit", latestTrackingStatus: "completed"))
        try storage.save(row)
        try storage.attachSwapTracking(txHash: row.txHash, pubKeyECDSA: row.pubKeyECDSA, providerKind: "swapKit",
                                        swapId: "late-id", routeId: "route", broadcastHash: row.txHash,
                                        sourceChainId: "1", subProvider: "provider")
        let restored = try XCTUnwrap(storage.fetch(id: row.id))
        XCTAssertEqual(restored.swapTracking?.latestTrackingStatus, "completed")
        XCTAssertEqual(restored.swapTracking?.swapId, "late-id")
    }

    func testLegacyCrossChainHashCollisionFailsClosed() throws {
        let container = try container()
        let storage = TransactionHistoryStorage(modelContext: container.mainContext)
        let original = ActivityTestFixture.row(hash: "same", chain: .ethereum)
        try storage.save(original)
        try storage.save(ActivityTestFixture.row(hash: "same", chain: .base, fee: "2 ETH"))
        XCTAssertEqual(try storage.fetchAll(pubKeyECDSA: original.pubKeyECDSA).count, 1)
        XCTAssertTrue(try storage.fetchByChain(pubKeyECDSA: original.pubKeyECDSA, chainRawValue: Chain.base.rawValue).isEmpty)
        XCTAssertEqual(try storage.fetch(id: original.id)?.feeCrypto, "")
    }

    func testNativeSwapDelayedAndDeleteWritesAllEmitAfterDurableSave() throws {
        let container = try container()
        let storage = TransactionHistoryStorage(modelContext: container.mainContext, publishesActivityEvents: true)
        var events: [String] = []
        let subscription = NotificationCenter.default.publisher(for: TransactionHistoryActivityEvent.notification).sink { notification in
            guard let event = notification.object as? TransactionHistoryActivityEvent else { return }
            switch event {
            case .saved(let row):
                XCTAssertNotNil(try? storage.fetch(id: row.id))
                events.append("saved")
            case .nativeStatus, .nativePending: events.append("native")
            case .swapStatus(let row, _):
                XCTAssertEqual(row.swapTracking?.latestTrackingStatus, "completed")
                XCTAssertEqual(try? storage.fetch(id: row.id)?.status, .successful)
                events.append("swap")
            case .delayed: events.append("delayed")
            case .deleted:
                XCTAssertEqual(try? container.mainContext.fetchCount(FetchDescriptor<TransactionHistoryItem>()), 0)
                events.append("deleted")
            }
        }
        defer { subscription.cancel() }
        let row = ActivityTestFixture.row(type: .swap, tracking: .init(providerKind: "swapKit"))
        try storage.save(row)
        try storage.updateStatus(txHash: row.txHash, pubKeyECDSA: row.pubKeyECDSA, status: .successful)
        try storage.updateSwapTrackingStatus(txHash: row.txHash, pubKeyECDSA: row.pubKeyECDSA,
                                             latestStatus: "completed", latestTrackingStatus: "completed",
                                             uiStatus: .completed, polledAt: Date())
        try storage.touchSwapTrackingLastPolled(txHash: row.txHash, pubKeyECDSA: row.pubKeyECDSA, polledAt: Date())
        try storage.deleteAll()
        XCTAssertEqual(events, ["saved", "native", "swap", "delayed", "deleted"])
    }

    func testUnchangedReceiptDoesNotEmitAnotherSave() throws {
        let container = try container()
        let storage = TransactionHistoryStorage(modelContext: container.mainContext, publishesActivityEvents: true)
        var savedCount = 0
        let subscription = NotificationCenter.default.publisher(for: TransactionHistoryActivityEvent.notification).sink { notification in
            if case .saved = notification.object as? TransactionHistoryActivityEvent { savedCount += 1 }
        }
        defer { subscription.cancel() }
        let row = ActivityTestFixture.row()
        try storage.save(row)
        try storage.save(row)
        XCTAssertEqual(savedCount, 1)
        try storage.save(ActivityTestFixture.row(hash: row.txHash, fee: "0.001 ETH"))
        XCTAssertEqual(savedCount, 2)
        try storage.save(ActivityTestFixture.row(hash: row.txHash, fee: "0.001 ETH"))
        XCTAssertEqual(savedCount, 2)
    }

    func testObservationSelectsExactVaultChainAndHashAndHonorsEmissionGate() throws {
        let container = try container()
        let storage = TransactionHistoryStorage(modelContext: container.mainContext, publishesActivityEvents: true)
        let row = ActivityTestFixture.row(hash: "same", vault: "one", chain: .ethereum)
        try storage.save(row)
        try storage.save(ActivityTestFixture.row(hash: "same", vault: "two", chain: .base))
        try storage.save(ActivityTestFixture.row(hash: "other", vault: "one", chain: .ethereum))
        var observedIDs: [UUID] = []
        let subscription = NotificationCenter.default.publisher(for: TransactionHistoryActivityEvent.notification).sink { notification in
            if case .nativePending(let value, _) = notification.object as? TransactionHistoryActivityEvent {
                observedIDs.append(value.id)
            }
        }
        defer { subscription.cancel() }
        storage.publishObservation(txHash: "same", pubKeyECDSA: "one", chain: .ethereum, isPending: true)
        storage.publishObservation(txHash: "same", pubKeyECDSA: "one", chain: .base, isPending: true)
        let silent = TransactionHistoryStorage(modelContext: container.mainContext)
        silent.publishObservation(txHash: "same", pubKeyECDSA: "one", chain: .ethereum, isPending: true)
        XCTAssertEqual(observedIDs, [row.id])
    }

    func testNotFoundGracePreservesRetryWithoutInventingAnObservation() async {
        var observations: [Bool] = []
        let action = await TransactionStatusPoller.nextAction(checker: ActivityStatusChecker(status: .notFound),
            txHash: "fixture", chain: .ethereum, deadlineReached: false, createdAt: Date(),
            onObservation: { observations.append($0) })
        XCTAssertEqual(action, .retry)
        XCTAssertTrue(observations.isEmpty)
    }

    func testNotFoundGraceUsesEachChainsPollingInterval() {
        let createdAt = Date()
        for chain in [Chain.ethereum, .bitcoin, .solana] {
            let interval = ChainStatusConfig.config(for: chain).pollInterval
            XCTAssertFalse(TransactionStatusPoller.shouldReportNotFound(createdAt: createdAt, chain: chain,
                                                                         now: createdAt.addingTimeInterval(interval - 0.1)))
            XCTAssertTrue(TransactionStatusPoller.shouldReportNotFound(createdAt: createdAt, chain: chain,
                                                                        now: createdAt.addingTimeInterval(interval)))
        }
    }

    func testFreshPendingAndNetworkFailureObservationsAreDistinct() async {
        var observations: [Bool] = []
        _ = await TransactionStatusPoller.nextAction(checker: ActivityStatusChecker(status: .pending),
                                                      txHash: "fixture", chain: .ethereum, deadlineReached: false,
                                                      onObservation: { observations.append($0) })
        _ = await TransactionStatusPoller.nextAction(checker: ActivityStatusChecker(status: .notFound),
                                                      txHash: "fixture", chain: .ethereum, deadlineReached: false,
                                                      onObservation: { observations.append($0) })
        _ = await TransactionStatusPoller.nextAction(checker: ActivityStatusChecker(status: nil),
                                                      txHash: "fixture", chain: .ethereum, deadlineReached: false,
                                                      onObservation: { observations.append($0) })
        XCTAssertEqual(observations, [true, false, false])
    }
}

private struct ActivityStatusChecker: TransactionStatusChecking {
    let status: TransactionStatusResult.TransactionConfirmationStatus?
    func checkTransactionStatus(txHash _: String, chain _: Chain) throws -> TransactionStatusResult {
        guard let status else { throw NSError(domain: "offline", code: 1) }
        return TransactionStatusResult(status: status, blockNumber: nil, confirmations: nil)
    }
}
