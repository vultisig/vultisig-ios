//
//  RelaySendRetryPolicy.swift
//  VultisigApp
//

import Foundation

/// Bounded retry for `POST /message/{sessionID}`. Repeating the send is safe:
/// the relay stores by `session-recipient-hash` and overwrites on repeat, and
/// receivers dedupe by the same key before applying.
///
/// The whole budget has to fit inside the ceremony stall limit. Peers keep
/// their own clocks running while this side retries, so a send that outlives
/// the stall restarts this party while the others are still waiting on it.
enum RelaySendRetryPolicy {
    static let maxAttempts = 4
    static let requestTimeout: TimeInterval = 8

    /// 1 s after the first failed attempt, then 2 s, then 4 s.
    static func backoff(afterAttempt attempt: Int) -> Duration {
        .seconds(1 << max(attempt - 1, 0))
    }

    /// Every attempt timing out, plus every backoff between attempts.
    static var worstCaseBudget: Duration {
        (1..<maxAttempts).reduce(.seconds(requestTimeout) * maxAttempts) { $0 + backoff(afterAttempt: $1) }
    }

    /// Transient transport faults and relay-side 5xx are retried. A 4xx, a
    /// cancellation, or a deterministic client-side failure is not.
    static func isRetryable(_ error: Error) -> Bool {
        if isCancellation(error) { return false }
        guard let httpError = error as? HTTPError else { return false }
        switch httpError {
        case .timeout:
            return true
        case .networkError(let underlying):
            return !isCancellation(underlying)
        case .statusCode(let code, _):
            return (500...599).contains(code)
        default:
            return false
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

enum RelaySendError: Error, LocalizedError {
    case invalidMessage(String)
    case rejected(status: Int)
    case exhausted(attempts: Int, lastError: Error)

    var errorDescription: String? {
        switch self {
        case .invalidMessage(let reason):
            return "fail to send message: \(reason)"
        case .rejected(let status):
            return "relay rejected message, status: \(status)"
        case .exhausted(let attempts, let lastError):
            return "fail to send message after \(attempts) attempts: \(lastError.localizedDescription)"
        }
    }
}
