#if os(iOS)
import BackgroundTasks
import UIKit

@MainActor
final class TransactionActivityBackgroundService {
    static let shared = TransactionActivityBackgroundService()
    static let refreshIdentifier = "com.vultisig.wallet.transaction-activity.refresh"
    private var registered = false
    private var connected = false
    private var pausedNativeTransactions = Set<UUID>()
    private let system = TransactionActivityBackgroundSystem()
    private var pollingSchedule = TransactionActivityPollingSchedule()
    private lazy var coordinator = TransactionLiveActivityCoordinator.shared
    private lazy var observer = TransactionActivityStatusRefresher(
        storage: .shared, checker: TransactionStatusService.shared,
        lookup: { TransactionLiveActivityCoordinator.shared.backgroundRecord(id: $0) },
        refreshSwap: { row, shouldApply in
            switch row.swapTracking?.providerKind {
            case SwapKitTrackingService.providerKind:
                await SwapKitTrackingService.shared.forceRefresh(tx: row, backgroundObservation: true, shouldApply: shouldApply)
            case NativeSwapTrackingService.providerKind:
                await NativeSwapTrackingService.shared.forceRefresh(tx: row, backgroundObservation: true, shouldApply: shouldApply)
            case THORChainLimitTrackingService.providerKind:
                await THORChainLimitTrackingService.shared.forceRefresh(tx: row, shouldApply: shouldApply)
            default: break
            }
        }, didCompleteSend: { TransactionStatusPoller.shared.notifyTransactionCompleted() }
    )
    private lazy var runner = TransactionActivityBackgroundRunner(
        runtime: system.runtime,
        hasWork: { TransactionLiveActivityCoordinator.shared.hasBackgroundWork },
        isForeground: { UIApplication.shared.applicationState != .background },
        nextPollDelay: { [weak self] in
            guard let self else { return TransactionActivityBackgroundRunner.minimumScheduleDelay }
            return self.pollingSchedule.nextDelay(for: self.coordinator.backgroundRecords)
        },
        refresh: { [weak self] in
            guard let self else { return }
            await self.coordinator.refreshInBackground { row in
                self.synchronizeProviderCadence(row)
                guard self.pollingSchedule.shouldObserve(row) else {
                    TransactionActivityDiagnostics.record("poll.skipped", recordID: row.id, detail: "reason=notDue")
                    return
                }
                TransactionActivityDiagnostics.record("poll.started", recordID: row.id)
                defer {
                    if LogGate.isEnabled(.wallet, .service) {
                        let phase = (try? TransactionHistoryStorage.shared.fetch(id: row.id)).map { TransactionActivityPolicy.phase(for: $0).rawValue } ?? "unavailable"
                        TransactionActivityDiagnostics.record("poll.finished", recordID: row.id, detail: "phase=\(phase) cancelled=\(Task.isCancelled)")
                    }
                }
                // The activity observer owns native transactions during the bounded window.
                if TransactionActivityPolicy.usesNativeStatus(row) {
                    self.pausedNativeTransactions.insert(row.id)
                    TransactionStatusPoller.shared.stopPolling(txHash: row.txHash)
                }
                await self.observer.refresh(row)
                if !Task.isCancelled { self.pollingSchedule.didObserve(row) }
            }
        }, drain: { await TransactionLiveActivityCoordinator.shared.waitForPendingUpdates() }
    )

    private func synchronizeProviderCadence(_ row: TransactionHistoryData) {
        guard row.swapTracking?.providerKind == THORChainLimitTrackingService.providerKind,
              let previous = THORChainLimitTrackingService.shared.lastPollDate(sender: row.fromAddress) else { return }
        pollingSchedule.didObserve(row, now: previous)
    }

    func register() {
        guard !registered else { return }
        registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshIdentifier, using: .main) { task in
            MainActor.assumeIsolated {
                TransactionActivityDiagnostics.record("scheduled.delivered", detail: "identifier=\(Self.refreshIdentifier)")
                // Do not cache an unreadable ledger during a pre-unlock background launch.
                guard TransactionActivityBackgroundService.shared.start() else {
                    TransactionActivityDiagnostics.record("scheduled.skipped", detail: "reason=protectedDataUnavailable")
                    task.setTaskCompleted(success: false)
                    return
                }
                let expire = TransactionActivityBackgroundService.shared.runner.performScheduledRefresh {
                    TransactionActivityDiagnostics.record("scheduled.completed", detail: "success=\($0)")
                    task.setTaskCompleted(success: $0)
                }
                task.expirationHandler = {
                    Task { @MainActor in
                        TransactionActivityDiagnostics.record("scheduled.expired", detail: "identifier=\(Self.refreshIdentifier)")
                        expire()
                    }
                }
            }
        }
        TransactionActivityDiagnostics.record("scheduler.registered", detail: "success=\(registered)")
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
        TransactionActivityDiagnostics.record("scene.background", detail: "refreshStatus=\(UIApplication.shared.backgroundRefreshStatus.rawValue)")
        guard start() else {
            TransactionActivityDiagnostics.record("window.skipped", detail: "reason=protectedDataUnavailable")
            return
        }
        runner.enteredBackground()
    }

    func enteredForeground() {
        guard start() else { return }
        runner.enteredForeground()
        pollingSchedule = TransactionActivityPollingSchedule()
        // Activity dismissal/permission changes must not disable normal wallet tracking.
        for id in pausedNativeTransactions {
            do {
                if let row = try TransactionHistoryStorage.shared.fetch(id: id), row.status == .inProgress,
                   try TransactionLiveActivityBroadcast.vaultExists(pubKey: row.pubKeyECDSA) {
                    TransactionStatusPoller.shared.poll(tx: row) { _, _ in }
                }
                pausedNativeTransactions.remove(id)
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
