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
            race.start(continuation)

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

    func start(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        defer { lock.unlock() }
        self.continuation = continuation
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
        guard !isFinished, let continuation else {
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
