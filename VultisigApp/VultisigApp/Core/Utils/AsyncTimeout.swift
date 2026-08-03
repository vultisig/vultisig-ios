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

/// Races `operation` against a wall-clock deadline.
///
/// A request-level timeout only bounds the gap *between* packets, so a server
/// that drips bytes indefinitely never trips it. Wrapping a call here bounds the
/// total elapsed time, which is what a UI waiting on the result actually cares
/// about.
///
/// The losing child task is cancelled before returning.
func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw AsyncTimeoutError(seconds: seconds)
        }

        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw AsyncTimeoutError(seconds: seconds)
        }
        return result
    }
}
