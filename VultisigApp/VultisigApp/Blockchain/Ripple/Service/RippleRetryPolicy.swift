//
//  RippleRetryPolicy.swift
//  VultisigApp
//

import Foundation
import OSLog

/// A decoded XRPL JSON-RPC response body that can surface a node-level error.
///
/// XRPL returns node/server errors (e.g. `amendmentBlocked`) as **HTTP 200**
/// with the error nested in the body (`result.error`), so retry detection reads
/// the decoded body rather than the HTTP status.
protocol RippleRPCResponse {
    /// The JSON-RPC error string the node returned, or `nil` on success.
    var rpcError: String? { get }
}

/// Pure classifier for "should this XRPL request be retried on the same host?".
///
/// The default XRPL host (`xrplcluster.com`) is a load-balanced **pool**, so a
/// retry against the same host is routed to a different backend — which is
/// almost always healthy. That is why the fix is a bounded same-host retry and
/// deliberately does NOT add a fallback host list.
enum RippleRetryPolicy {
    /// Total attempts for a request = one initial try plus up to
    /// `maxAttempts - 1` retries. Kept small so the post-signing broadcast
    /// window stays responsive.
    static let maxAttempts = 3

    /// JSON-RPC `result.error` values that indicate a transient/stale backend in
    /// the pool. A same-host retry routes to a different (healthy) node.
    ///
    /// `tooBusy` / `slowDown` are per-backend overload signals emitted by the
    /// node (not the pool edge), so a pool retry lands on a different node; they
    /// stay bounded by `maxAttempts` and the backoff, so including them is safe.
    static let retryableRPCErrors: Set<String> = [
        "amendmentBlocked",
        "noNetwork",
        "noCurrent",
        "noClosed",
        "tooBusy",
        "slowDown",
        // Clio forwards write/server commands (submit, server_state, fee) to a
        // rippled backend; a forwarding failure is a transient per-node fault a
        // same-host pool retry can route around.
        "failedToForward"
    ]

    /// Whether a decoded node error warrants a same-host retry. Business errors
    /// (`actNotFound`, `txnNotFound`, `invalidParams`, engine `tef*`/`tec*`
    /// codes, …) are not transient and pass through unchanged.
    static func isRetryable(rpcError: String?) -> Bool {
        guard let rpcError else { return false }
        return retryableRPCErrors.contains(rpcError)
    }

    /// Whether a thrown transport error is transient and worth a retry. A
    /// cancellation is never retried, even when wrapped in `.networkError`.
    static func isRetryable(transportError error: Error) -> Bool {
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

    /// Task cancellation in any of its forms, which must never be retried.
    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    /// Linear backoff before the given retry (1-based over the retries):
    /// retry 1 → 0.25s, retry 2 → 0.5s. Short enough to keep added latency low
    /// in the time-sensitive broadcast window.
    static func backoff(forAttempt attempt: Int) -> Duration {
        .milliseconds(250 * max(attempt, 1))
    }
}

/// Raised when the bounded same-host retry is exhausted and the node still
/// returned a transient error. Surfacing it (rather than returning the stale
/// body) stops callers that don't inspect `rpcError` from treating an
/// `amendmentBlocked` reply as valid data (e.g. a `0` XRP balance).
enum RippleRetryError: Error, LocalizedError {
    case exhausted(rpcError: String)

    var errorDescription: String? {
        switch self {
        case .exhausted(let rpcError):
            return "XRPL request failed after retries (\(rpcError))"
        }
    }
}

/// Wraps `HTTPClientProtocol` request execution with the bounded same-host
/// retry defined by `RippleRetryPolicy`. Shared by `RippleService` and
/// `RippleTransactionStatusProvider` so broadcast, status, and reads all
/// benefit. The sleeper is injected so tests drive it with a no-op clock.
struct RippleRequestRetrier {
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    /// Production sleeper: suspends for the requested duration.
    static let defaultSleep: Sleeper = { try await Task.sleep(for: $0) }

    private let httpClient: HTTPClientProtocol
    private let sleep: Sleeper
    private let logger: Logger

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        sleep: @escaping Sleeper = RippleRequestRetrier.defaultSleep,
        logger: Logger = Logger(subsystem: "com.vultisig.app", category: "ripple-retry")
    ) {
        self.httpClient = httpClient
        self.sleep = sleep
        self.logger = logger
    }

    /// Performs `target`, retrying on the SAME host while the decoded body or a
    /// thrown transport error is transient, up to `RippleRetryPolicy.maxAttempts`.
    /// A non-retryable node error is returned as-is so the caller surfaces it
    /// exactly as before; a *retryable* error that survives the whole budget is
    /// thrown as `RippleRetryError.exhausted` rather than returned as data.
    func request<T: Decodable & RippleRPCResponse>(
        _ target: TargetType,
        responseType: T.Type
    ) async throws -> T {
        let retryCap = RippleRetryPolicy.maxAttempts - 1
        var attempt = 1
        while true {
            do {
                let body = try await httpClient.request(target, responseType: responseType).data
                guard let rpcError = body.rpcError,
                      RippleRetryPolicy.isRetryable(rpcError: rpcError) else {
                    return body
                }
                guard attempt < RippleRetryPolicy.maxAttempts else {
                    logger.error("XRPL request exhausted \(retryCap, privacy: .public) retries; surfacing node error '\(rpcError, privacy: .public)'")
                    throw RippleRetryError.exhausted(rpcError: rpcError)
                }
                logger.info("Retrying XRPL request after node error '\(rpcError, privacy: .public)' (retry \(attempt, privacy: .public)/\(retryCap, privacy: .public))")
                try await sleep(RippleRetryPolicy.backoff(forAttempt: attempt))
                attempt += 1
            } catch let retryError as RippleRetryError {
                throw retryError
            } catch {
                guard RippleRetryPolicy.isRetryable(transportError: error),
                      attempt < RippleRetryPolicy.maxAttempts else {
                    throw error
                }
                logger.info("Retrying XRPL request after transport error (retry \(attempt, privacy: .public)/\(retryCap, privacy: .public)): \(error.localizedDescription, privacy: .public)")
                try await sleep(RippleRetryPolicy.backoff(forAttempt: attempt))
                attempt += 1
            }
        }
    }
}
