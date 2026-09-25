#if os(iOS)
import Foundation

/// Owns one OS-granted execution window. Expiration never waits for network cleanup.
@MainActor
final class TransactionActivityBackgroundRunner {
    struct Runtime {
        var begin: (@escaping @MainActor () -> Void) -> UUID?
        var end: (UUID) -> Void
        var schedule: (Date) throws -> Void
        var cancelScheduled: () -> Void
    }

    private final class Run {
        let id = UUID()
        var assertion: UUID?
        var worker: Task<Void, Never>?
        var deadline: Task<Void, Never>?
        var observationDeadline: Task<Void, Never>?
        var draining: Task<Void, Never>?
        let completion: ((Bool) -> Void)?
        init(completion: ((Bool) -> Void)?) { self.completion = completion }
    }

    /// Requested `earliestBeginDate` never goes below this, regardless of `nextPollDelay()`.
    /// The OS treats it as a minimum anyway; a smaller request just burns background budget.
    static let minimumScheduleDelay: TimeInterval = 60

    private let runtime: Runtime
    private let hasWork: () -> Bool
    private let isForeground: () -> Bool
    private let nextPollDelay: () -> TimeInterval
    private let refresh: () async -> Void
    private let drain: () async -> Void
    private let sleep: (Duration) async throws -> Void
    private var run: Run?
    private var scheduleAttempted = false

    init(runtime: Runtime, hasWork: @escaping () -> Bool, isForeground: @escaping () -> Bool,
         nextPollDelay: @escaping () -> TimeInterval, refresh: @escaping () async -> Void, drain: @escaping () async -> Void = {},
         sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.runtime = runtime
        self.hasWork = hasWork
        self.isForeground = isForeground
        self.nextPollDelay = nextPollDelay
        self.refresh = refresh
        self.drain = drain
        self.sleep = sleep
    }

    func enteredBackground() {
        TransactionActivityDiagnostics.record("background.enter", detail: "hasWork=\(hasWork()) running=\(run != nil)")
        guard !isForeground(), run == nil else {
            TransactionActivityDiagnostics.record("window.skipped", detail: "reason=\(isForeground() ? "foreground" : "alreadyRunning")")
            return
        }
        scheduleAttempted = false
        updateSchedule()
        guard hasWork() else {
            TransactionActivityDiagnostics.record("window.skipped", detail: "reason=noWork")
            return
        }
        let current = Run(completion: nil)
        run = current
        let assertion = runtime.begin { [weak self] in self?.finish(id: current.id, success: false, reason: "osExpiration") }
        guard run?.id == current.id else {
            if let assertion { runtime.end(assertion) }
            return
        }
        guard let assertion else { finish(id: current.id, success: false, reason: "assertionDenied"); return }
        current.assertion = assertion
        TransactionActivityDiagnostics.record("window.acquired", runID: current.id)
        launch(current, mode: "backgroundEntry")
    }

    func enteredForeground() {
        TransactionActivityDiagnostics.record("foreground.enter")
        if let run { finish(id: run.id, success: false, reason: "foreground") }
    }

    /// Returns the expiration hook for exactly this delivery, never a later replacement.
    func performScheduledRefresh(completion: @escaping (Bool) -> Void) -> () -> Void {
        scheduleAttempted = false
        if run != nil {
            TransactionActivityDiagnostics.record("scheduled.skipped", detail: "reason=windowAlreadyRunning")
            // A scheduled delivery must not replace the immediate continuation window.
            completion(true)
            updateSchedule()
            return {}
        }
        let current = Run(completion: completion)
        run = current
        if isForeground() || !hasWork() {
            finish(id: current.id, success: true, reason: "foregroundOrNoWork")
        } else {
            launch(current, mode: "scheduled")
        }
        return { [weak self] in self?.finish(id: current.id, success: false, reason: "osExpiration") }
    }

    func trackingDidChange() {
        guard !hasWork() else { return }
        if let run { finish(id: run.id, success: true, reason: "noWork") }
        updateSchedule()
    }

    private func launch(_ current: Run, mode: String) {
        TransactionActivityDiagnostics.record("window.started", runID: current.id, detail: "mode=\(mode)")
        current.deadline = Task { [weak self, sleep] in
            do { try await sleep(.seconds(25)) } catch { return }
            self?.finish(id: current.id, success: false, reason: "executionDeadline")
        }
        current.observationDeadline = Task { [weak self, sleep] in
            do { try await sleep(.seconds(22)) } catch { return }
            guard let self, self.run?.id == current.id else { return }
            TransactionActivityDiagnostics.record("window.observationDeadline", runID: current.id)
            current.worker?.cancel()
            current.draining = Task { [weak self, drain] in
                await drain()
                self?.finish(id: current.id, success: false, reason: "observationDeadline")
            }
        }
        current.worker = Task { [weak self, refresh] in
            guard !Task.isCancelled, let self, self.run?.id == current.id else { return }
            guard !self.isForeground(), self.hasWork() else {
                self.finish(id: current.id, success: true, reason: "foregroundOrNoWork")
                return
            }
            TransactionActivityDiagnostics.record("poll.batchStarted", runID: current.id)
            await refresh()
            TransactionActivityDiagnostics.record("poll.batchReturned", runID: current.id, detail: "cancelled=\(Task.isCancelled)")
            guard !Task.isCancelled, self.run?.id == current.id else { return }
            self.finish(id: current.id, success: true, reason: "observationFinished")
        }
    }

    private func finish(id: UUID, success: Bool, reason: String) {
        guard let current = run, current.id == id else { return }
        TransactionActivityDiagnostics.record("window.finished", runID: id, detail: "reason=\(reason) success=\(success)")
        run = nil
        current.worker?.cancel()
        current.deadline?.cancel()
        current.observationDeadline?.cancel()
        current.draining?.cancel()
        if let assertion = current.assertion { runtime.end(assertion) }
        current.completion?(success)
        updateSchedule()
    }

    private func updateSchedule() {
        guard hasWork() else {
            TransactionActivityDiagnostics.record("schedule.cancelRequested", detail: "reason=noBackgroundWork")
            runtime.cancelScheduled()
            // Cancellation has no result payload; do not claim a pending request existed.
            TransactionActivityDiagnostics.record("schedule.cancelReturned", detail: "reason=noBackgroundWork")
            scheduleAttempted = false
            return
        }
        guard !isForeground() else {
            TransactionActivityDiagnostics.record("schedule.skipped", detail: "reason=foreground")
            return
        }
        guard !scheduleAttempted else {
            TransactionActivityDiagnostics.record("schedule.skipped", detail: "reason=alreadyAttempted")
            return
        }
        scheduleAttempted = true
        // earliestBeginDate is a floor, not a promise; iOS decides the actual delivery time.
        let delay = max(Self.minimumScheduleDelay, nextPollDelay())
        let date = Date().addingTimeInterval(delay)
        TransactionActivityDiagnostics.record("schedule.requested", detail: "earliestBegin=\(date.ISO8601Format()) delaySeconds=\(delay)")
        do {
            try runtime.schedule(date)
            TransactionActivityDiagnostics.record("schedule.accepted", detail: "earliestBegin=\(date.ISO8601Format()) delaySeconds=\(delay)")
        } catch {
            // Do not log error descriptions/userInfo, which can include request data.
            let code = (error as NSError).code
            TransactionActivityDiagnostics.record("schedule.failed", detail: "earliestBegin=\(date.ISO8601Format()) code=\(code)")
        }
    }
}
#endif
