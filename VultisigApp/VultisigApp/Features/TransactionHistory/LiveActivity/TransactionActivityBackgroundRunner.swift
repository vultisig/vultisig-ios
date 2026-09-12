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

    private let runtime: Runtime
    private let hasWork: () -> Bool
    private let isForeground: () -> Bool
    private let refresh: () async -> Void
    private let drain: () async -> Void
    private let sleep: (Duration) async throws -> Void
    private var run: Run?
    private var scheduleAttempted = false

    init(runtime: Runtime, hasWork: @escaping () -> Bool, isForeground: @escaping () -> Bool,
         refresh: @escaping () async -> Void, drain: @escaping () async -> Void = {},
         sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.runtime = runtime
        self.hasWork = hasWork
        self.isForeground = isForeground
        self.refresh = refresh
        self.drain = drain
        self.sleep = sleep
    }

    func enteredBackground() {
        guard !isForeground(), run == nil else { return }
        scheduleAttempted = false
        updateSchedule()
        guard hasWork() else { return }
        let current = Run(completion: nil)
        run = current
        let assertion = runtime.begin { [weak self] in self?.finish(id: current.id, success: false) }
        guard run?.id == current.id else {
            if let assertion { runtime.end(assertion) }
            return
        }
        guard let assertion else { finish(id: current.id, success: false); return }
        current.assertion = assertion
        launch(current, repeating: true)
    }

    func enteredForeground() {
        if let run { finish(id: run.id, success: false) }
    }

    /// Returns the expiration hook for exactly this delivery, never a later replacement.
    func performScheduledRefresh(completion: @escaping (Bool) -> Void) -> () -> Void {
        scheduleAttempted = false
        if run != nil {
            // A scheduled delivery must not replace the immediate continuation window.
            completion(true)
            updateSchedule()
            return {}
        }
        let current = Run(completion: completion)
        run = current
        if isForeground() || !hasWork() {
            finish(id: current.id, success: true)
        } else {
            launch(current, repeating: false)
        }
        return { [weak self] in self?.finish(id: current.id, success: false) }
    }

    func trackingDidChange() {
        guard !hasWork() else { return }
        if let run { finish(id: run.id, success: true) }
        updateSchedule()
    }

    private func launch(_ current: Run, repeating: Bool) {
        current.deadline = Task { [weak self, sleep] in
            do { try await sleep(.seconds(25)) } catch { return }
            self?.finish(id: current.id, success: false)
        }
        current.observationDeadline = Task { [weak self, sleep] in
            do { try await sleep(.seconds(22)) } catch { return }
            guard let self, self.run?.id == current.id else { return }
            current.worker?.cancel()
            current.draining = Task { [weak self, drain] in
                await drain()
                self?.finish(id: current.id, success: false)
            }
        }
        current.worker = Task { [weak self, refresh, sleep] in
            repeat {
                guard !Task.isCancelled, let self, self.run?.id == current.id else { return }
                guard !self.isForeground(), self.hasWork() else {
                    self.finish(id: current.id, success: true)
                    return
                }
                await refresh()
                guard !Task.isCancelled, self.run?.id == current.id else { return }
                if !repeating || !self.hasWork() {
                    self.finish(id: current.id, success: true)
                    return
                }
                do { try await sleep(.seconds(10)) } catch { return }
            } while !Task.isCancelled
        }
    }

    private func finish(id: UUID, success: Bool) {
        guard let current = run, current.id == id else { return }
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
            runtime.cancelScheduled()
            scheduleAttempted = false
            return
        }
        guard !isForeground(), !scheduleAttempted else { return }
        scheduleAttempted = true
        do {
            try runtime.schedule(Date().addingTimeInterval(15 * 60))
        } catch {
            // Denial (including Background App Refresh disabled) leaves local continuation usable.
        }
    }
}
#endif
