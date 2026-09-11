#if os(iOS)
import BackgroundTasks
import UIKit

@MainActor
final class TransactionActivityBackgroundService {
    static let shared = TransactionActivityBackgroundService()
    static let refreshIdentifier = "com.vultisig.wallet.transaction-activity.refresh"
    private var registered = false
    private var connected = false
    private var pausedSends = Set<UUID>()
    private let system = TransactionActivityBackgroundSystem()
    private lazy var coordinator = TransactionLiveActivityCoordinator.shared
    private lazy var observer = TransactionActivityStatusRefresher(
        storage: .shared, checker: TransactionStatusService.shared,
        lookup: { TransactionLiveActivityCoordinator.shared.backgroundRecord(id: $0) },
        refreshSwap: { row, shouldApply in
            await SwapKitTrackingService.shared.forceRefresh(tx: row, backgroundObservation: true, shouldApply: shouldApply)
        }, didCompleteSend: { TransactionStatusPoller.shared.notifyTransactionCompleted() }
    )
    private lazy var runner = TransactionActivityBackgroundRunner(
        runtime: system.runtime,
        hasWork: { TransactionLiveActivityCoordinator.shared.hasBackgroundWork },
        isForeground: { UIApplication.shared.applicationState != .background },
        refresh: { [weak self] in
            guard let self else { return }
            await self.coordinator.refreshInBackground { row in
                // The activity observer owns these sends during the bounded window.
                if row.type == .send {
                    self.pausedSends.insert(row.id)
                    TransactionStatusPoller.shared.stopPolling(txHash: row.txHash)
                }
                await self.observer.refresh(row)
            }
        }, drain: { await TransactionLiveActivityCoordinator.shared.waitForPendingUpdates() }
    )

    func register() {
        guard !registered else { return }
        registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshIdentifier, using: .main) { task in
            MainActor.assumeIsolated {
                // Do not cache an unreadable ledger during a pre-unlock background launch.
                guard TransactionActivityBackgroundService.shared.start() else {
                    task.setTaskCompleted(success: false)
                    return
                }
                let expire = TransactionActivityBackgroundService.shared.runner.performScheduledRefresh {
                    task.setTaskCompleted(success: $0)
                }
                task.expirationHandler = { Task { @MainActor in expire() } }
            }
        }
    }

    @discardableResult
    func start() -> Bool {
        if connected { return true }
        let ledger = UserDefaults.standard.data(forKey: TransactionActivityPolicy.ledgerKey)
        guard Self.canInitialize(protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable, ledger: ledger) else { return false }
        connected = true
        coordinator.backgroundWorkDidChange = { [weak self] in self?.runner.trackingDidChange() }
        return true
    }

    /// A locked device can still read after-first-unlock data. Do not disable its refreshes.
    static func canInitialize(protectedDataAvailable: Bool, ledger: Data?) -> Bool {
        if protectedDataAvailable { return true }
        guard let ledger else { return false }
        return (try? JSONDecoder().decode([String: TransactionLiveActivityCoordinator.Binding].self, from: ledger)) != nil
    }

    func enteredBackground() {
        guard start() else { return }
        runner.enteredBackground()
    }

    func enteredForeground() {
        guard start() else { return }
        runner.enteredForeground()
        // Activity dismissal/permission changes must not disable normal wallet tracking.
        for id in pausedSends {
            do {
                if let row = try TransactionHistoryStorage.shared.fetch(id: id), row.status == .inProgress,
                   try TransactionLiveActivityBroadcast.vaultExists(pubKey: row.pubKeyECDSA) {
                    TransactionStatusPoller.shared.poll(tx: row) { _, _ in }
                }
                pausedSends.remove(id)
            } catch { continue }
        }
    }
}

/// Platform boundary for native background assertions and scheduled refresh requests.
@MainActor
final class TransactionActivityBackgroundSystem {
    private var assertions: [UUID: UIBackgroundTaskIdentifier] = [:]

    var runtime: TransactionActivityBackgroundRunner.Runtime {
        .init(begin: { [self] expiration in
            let id = UUID()
            let assertion = UIApplication.shared.beginBackgroundTask(withName: "Transaction Live Activity") {
                MainActor.assumeIsolated { expiration() }
            }
            guard assertion != .invalid else { return nil }
            assertions[id] = assertion
            return id
        }, end: { [self] id in
            guard let assertion = assertions.removeValue(forKey: id) else { return }
            UIApplication.shared.endBackgroundTask(assertion)
        }, schedule: { date in
            let request = BGAppRefreshTaskRequest(identifier: TransactionActivityBackgroundService.refreshIdentifier)
            request.earliestBeginDate = date
            try BGTaskScheduler.shared.submit(request)
        }, cancelScheduled: {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: TransactionActivityBackgroundService.refreshIdentifier)
        })
    }
}
#endif
