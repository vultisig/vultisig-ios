//
//  AsyncTimeout.swift
//  VultisigApp
//

import Foundation

/// Thrown by `withTimeout(seconds:operation:)` when the deadline wins the race.
struct AsyncTimeoutError: LocalizedError {
    let seconds: TimeInterval

    var errorDescription: String? {
        "Operation timed out after \(seconds)s"
    }
}

/// Runs `operation` with a hard wall-clock bound.
///
/// A request-level timeout only bounds the gap *between* packets, so a server
/// that drips bytes indefinitely never trips it. This bounds total elapsed time,
/// which is what a UI waiting on the result actually cares about.
///
/// Deliberately *not* built on a task group: a group does not return until every
/// child has finished, so an operation that ignores cancellation would keep the
/// call suspended past the deadline — exactly the hang the timeout exists to
/// prevent. Instead the operation and the timer race to resolve a single
/// continuation; the first to finish wins and the loser is cancelled. When the
/// deadline wins, this returns immediately and the operation is abandoned rather
/// than awaited.
func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let race = AsyncTimeoutRace<T>()

    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            // A task cancelled before this point already delivered its result to
            // the race, and `start` consumes it. Bail out before spawning
            // anything so an abandoned load never fires its request.
            guard race.start(continuation) else { return }

            race.track(Task {
                do {
                    race.resume(.success(try await operation()))
                } catch {
                    race.resume(.failure(error))
                }
            })

            race.track(Task {
                do {
                    try await Task.sleep(for: .seconds(seconds))
                    race.resume(.failure(AsyncTimeoutError(seconds: seconds)))
                } catch {
                    // Cancelled because the operation already won the race.
                }
            })
        }
    } onCancel: {
        race.resume(.failure(CancellationError()))
    }
}

/// One-shot continuation guard shared by the operation and the timer. Only the
/// first `resume` takes effect; it also cancels every racer so the loser stops
/// as soon as it reaches a suspension point.
private final class AsyncTimeoutRace<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var racers: [Task<Void, Never>] = []
    private var isFinished = false
    /// A terminal result that arrived before the continuation existed. The
    /// cancellation handler fires immediately for an already-cancelled task —
    /// i.e. before the continuation body runs — so without this the cancellation
    /// would be dropped and the racers would start anyway.
    private var pendingResult: Result<T, Error>?

    /// Installs the continuation. Returns `false` when a terminal result had
    /// already arrived, in which case it is delivered here and the caller must
    /// not start any racers.
    func start(_ continuation: CheckedContinuation<T, Error>) -> Bool {
        lock.lock()
        guard let pendingResult else {
            self.continuation = continuation
            lock.unlock()
            return true
        }
        isFinished = true
        self.pendingResult = nil
        lock.unlock()

        continuation.resume(with: pendingResult)
        return false
    }

    /// Registers a racer. If the race is already decided the task is cancelled
    /// straight away, which covers an operation that finishes before its
    /// competitor has even been registered.
    func track(_ task: Task<Void, Never>) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            task.cancel()
            return
        }
        racers.append(task)
        lock.unlock()
    }

    func resume(_ result: Result<T, Error>) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        guard let continuation else {
            // Nothing to resume yet — hold the first terminal result for `start`.
            if pendingResult == nil {
                pendingResult = result
            }
            lock.unlock()
            return
        }
        isFinished = true
        self.continuation = nil
        let losers = racers
        racers = []
        lock.unlock()

        continuation.resume(with: result)
        losers.forEach { $0.cancel() }
    }
}
