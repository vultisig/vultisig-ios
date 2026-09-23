//
//  PendingTransactionManagerPollingTests.swift
//  VultisigAppTests
//
//  `PendingTransactionManager` keeps at most one poller per chain. Deciding
//  that a chain needs a poller and registering it must be one step, and every
//  poller that leaves the registry must be cancelled; otherwise a poller keeps
//  running untracked and nothing can stop it.
//
//  The stand-in pollers park until cancelled, so a leaked one stays visible as
//  a live task.
//

@testable import VultisigApp
import XCTest

final class PendingTransactionManagerPollingTests: XCTestCase {

    // MARK: - Start

    func testConcurrentStartsForOneChainLeaveExactlyOneLivePoller() {
        let (manager, _, recorder) = makeManager()
        addPending("tx-1", chain: .thorChain, to: manager)

        for round in 1...50 {
            manager.stopPollingForChain(.thorChain)
            XCTAssertTrue(recorder.livePollers.isEmpty)

            DispatchQueue.concurrentPerform(iterations: 64) { _ in
                manager.startPollingForChain(.thorChain)
            }

            XCTAssertEqual(recorder.created.count, round + 1, "round \(round): only one concurrent start may build a poller")
            XCTAssertEqual(recorder.livePollers.count, 1, "round \(round)")
        }
    }

    func testStartWithoutPendingTransactionsCreatesNoPoller() {
        let (manager, _, recorder) = makeManager()

        manager.startPollingForChain(.thorChain)

        XCTAssertTrue(recorder.created.isEmpty)
    }

    func testRunningPollerIsNotDuplicated() {
        let (manager, _, recorder) = makeManager()
        addPending("tx-1", chain: .thorChain, to: manager)
        addPending("tx-2", chain: .thorChain, to: manager)

        manager.startPollingForChain(.thorChain)

        XCTAssertEqual(recorder.created.count, 1)
        XCTAssertEqual(recorder.livePollers.count, 1)
    }

    // MARK: - Stop / start sequencing

    func testStartAfterStopStartsAFreshPoller() {
        let (manager, _, recorder) = makeManager()
        addPending("tx-1", chain: .thorChain, to: manager)
        let first = recorder.created[0]

        manager.stopPollingForChain(.thorChain)
        XCTAssertTrue(first.isCancelled)

        manager.startPollingForChain(.thorChain)
        XCTAssertEqual(recorder.created.count, 2, "a stopped poller must not block the next start")
        XCTAssertEqual(recorder.livePollers, [recorder.created[1]])
    }

    func testStopAllPollingCancelsEveryPollerAndAllowsRestart() {
        let (manager, _, recorder) = makeManager()
        addPending("tx-thor", chain: .thorChain, to: manager)
        addPending("tx-maya", chain: .mayaChain, to: manager)
        XCTAssertEqual(recorder.livePollers.count, 2)

        manager.stopAllPolling()
        XCTAssertTrue(recorder.livePollers.isEmpty)

        manager.startPollingForChain(.thorChain)
        XCTAssertEqual(recorder.created.count, 3)
        XCTAssertEqual(recorder.livePollers.count, 1)
    }

    func testConcurrentStartsAndStopsLeaveNoPollerRunningUntracked() {
        let (manager, _, recorder) = makeManager()
        addPending("tx-1", chain: .thorChain, to: manager)

        for round in 1...50 {
            DispatchQueue.concurrentPerform(iterations: 64) { index in
                if index.isMultiple(of: 2) {
                    manager.startPollingForChain(.thorChain)
                } else {
                    manager.stopPollingForChain(.thorChain)
                }
            }
            XCTAssertLessThanOrEqual(recorder.livePollers.count, 1, "round \(round)")

            manager.stopPollingForChain(.thorChain)
            XCTAssertTrue(recorder.livePollers.isEmpty, "round \(round): a poller outlived stop, so it was not registered")
        }
    }

    // MARK: - Idle stop

    /// A poller decides to stop from an earlier look at the pending set. A
    /// transaction added since then must keep it running.
    func testIdleStopKeepsThePollerWhileATransactionIsPending() {
        let (manager, _, recorder) = makeManager()
        addPending("tx-1", chain: .thorChain, to: manager)

        manager.stopPollingIfIdle(.thorChain)

        XCTAssertEqual(recorder.livePollers.count, 1)
        manager.startPollingForChain(.thorChain)
        XCTAssertEqual(recorder.created.count, 1, "the poller must still be registered")
    }

    func testIdleStopStopsThePollerOnceNothingIsPending() {
        let (manager, store, recorder) = makeManager()
        addPending("tx-1", chain: .thorChain, to: manager)
        addPending("tx-maya", chain: .mayaChain, to: manager)

        store.remove("tx-1")
        manager.stopPollingIfIdle(.thorChain)

        XCTAssertTrue(recorder.created[0].isCancelled)
        XCTAssertEqual(recorder.livePollers, [recorder.created[1]], "another chain's poller is unaffected")
    }

    // MARK: - Helpers

    private func makeManager() -> (PendingTransactionManager, ThreadSafeDictionary<String, PendingTransaction>, PollerRecorder) {
        let store = ThreadSafeDictionary<String, PendingTransaction>()
        let recorder = PollerRecorder()
        let manager = PendingTransactionManager(
            pendingTransactions: store,
            pollingTaskFactory: { _ in recorder.makePoller() }
        )
        addTeardownBlock { recorder.cancelAll() }
        return (manager, store, recorder)
    }

    private func addPending(_ txHash: String, chain: Chain, to manager: PendingTransactionManager) {
        manager.addPendingTransaction(txHash: txHash, address: "address-\(txHash)", chain: chain, sequence: 1)
    }
}

private final class PollerRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [Task<Void, Never>] = []

    var created: [Task<Void, Never>] {
        lock.withLock { tasks }
    }

    var livePollers: [Task<Void, Never>] {
        created.filter { !$0.isCancelled }
    }

    func makePoller() -> Task<Void, Never> {
        let task = Task {
            _ = try? await Task.sleep(for: .seconds(3600))
        }
        lock.withLock { tasks.append(task) }
        return task
    }

    func cancelAll() {
        for task in created {
            task.cancel()
        }
    }
}
