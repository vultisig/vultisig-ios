#if os(iOS)
import Combine
import SwiftData
import XCTest
@testable import VultisigApp

@MainActor
final class TransactionActivityStatusRefresherTests: XCTestCase {
    private func storage() throws -> (ModelContainer, TransactionHistoryStorage) {
        let schema = Schema([TransactionHistoryItem.self, SwapTrackingMetadata.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return (container, TransactionHistoryStorage(modelContext: container.mainContext, publishesActivityEvents: true))
    }

    private func refresher(_ storage: TransactionHistoryStorage, checker: NativeActivityChecker,
                           lookup: TransactionActivityStatusRefresher.Lookup? = nil) -> TransactionActivityStatusRefresher {
        TransactionActivityStatusRefresher(storage: storage, checker: checker,
                                           lookup: lookup ?? { try? storage.fetch(id: $0) },
                                           refreshSwap: { _, _ in XCTFail("Native sends must not call the swap tracker") })
    }

    func testSendObservationsKeepOutcomeSeparateFromFreshness() async throws {
        let statuses: [TransactionStatusResult.TransactionConfirmationStatus?] = [.confirmed, .failed(reason: "reverted"), .pending, .notFound, nil]
        for (index, status) in statuses.enumerated() {
            let (container, storage) = try storage()
            let row = ActivityTestFixture.row()
            try storage.save(row)
            var events: [String] = []
            let subscription = NotificationCenter.default.publisher(for: TransactionHistoryActivityEvent.notification).sink { notification in
                switch notification.object as? TransactionHistoryActivityEvent {
                case .nativeStatus: events.append("terminal")
                case .nativePending: events.append("pending")
                case .delayed: events.append("delayed")
                default: break
                }
            }
            await refresher(storage, checker: NativeActivityChecker(status: status)).refresh(row)
            let updated = try XCTUnwrap(storage.fetch(id: row.id))
            XCTAssertEqual(updated.status, index == 0 ? .successful : index == 1 ? .error : .inProgress)
            XCTAssertEqual(events, [index < 2 ? "terminal" : index == 2 ? "pending" : "delayed"])
            subscription.cancel()
            withExtendedLifetime(container) {}
        }
    }

    func testCancellationDiscardsLateChainSuccess() async throws {
        let (container, storage) = try storage()
        let row = ActivityTestFixture.row()
        try storage.save(row)
        let worker = refresher(storage, checker: NativeActivityChecker(status: .confirmed, cancelBeforeReturning: true))
        let task = Task { await worker.refresh(row) }
        await task.value
        XCTAssertEqual(try storage.fetch(id: row.id)?.status, .inProgress)
        withExtendedLifetime(container) {}
    }

    func testDeletedOrDismissedRecordCannotApplyLateSuccess() async throws {
        let (container, storage) = try storage()
        let row = ActivityTestFixture.row()
        try storage.save(row)
        var isTracked = true
        let checker = NativeActivityChecker(status: .confirmed, beforeReturning: { isTracked = false })
        let worker = refresher(storage, checker: checker, lookup: { isTracked ? try? storage.fetch(id: $0) : nil })
        await worker.refresh(row)
        XCTAssertEqual(try storage.fetch(id: row.id)?.status, .inProgress)
        withExtendedLifetime(container) {}
    }

    func testAnExistingTerminalResultIsNotOverwritten() async throws {
        let (container, storage) = try storage()
        let row = ActivityTestFixture.row()
        try storage.save(row)
        let checker = NativeActivityChecker(status: .confirmed, beforeReturning: {
            try? storage.updateActivitySendStatus(id: row.id, status: .error, errorMessage: "reverted", observedAt: Date())
        })
        await refresher(storage, checker: checker).refresh(row)
        XCTAssertEqual(try storage.fetch(id: row.id)?.status, .error)
        withExtendedLifetime(container) {}
    }

    func testSwapRefreshUsesProviderAndRevalidatesItsTrackingIdentifiers() async throws {
        let (container, storage) = try storage()
        let row = ActivityTestFixture.row(type: .swap, tracking: .init(providerKind: "swapKit", broadcastHash: "source", sourceChainId: "1"))
        try storage.save(row)
        var tracked: TransactionHistoryData? = row
        var calls = 0
        let worker = TransactionActivityStatusRefresher(storage: storage, checker: NativeActivityChecker(status: nil),
                                                        lookup: { _ in tracked }, refreshSwap: { _, shouldApply in
            calls += 1
            XCTAssertTrue(shouldApply())
            tracked = nil
            XCTAssertFalse(shouldApply())
        })
        await worker.refresh(row)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try storage.fetch(id: row.id)?.status, .inProgress)
        withExtendedLifetime(container) {}
    }
}

private struct NativeActivityChecker: TransactionStatusChecking {
    let status: TransactionStatusResult.TransactionConfirmationStatus?
    var cancelBeforeReturning = false
    var beforeReturning: @MainActor @Sendable () -> Void = {}

    func checkTransactionStatus(txHash _: String, chain _: Chain) async throws -> TransactionStatusResult {
        await beforeReturning()
        if cancelBeforeReturning { withUnsafeCurrentTask { $0?.cancel() } }
        guard let status else { throw URLError(.notConnectedToInternet) }
        return TransactionStatusResult(status: status, blockNumber: nil, confirmations: nil)
    }
}
#endif
