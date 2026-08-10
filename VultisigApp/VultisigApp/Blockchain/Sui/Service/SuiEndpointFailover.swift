//
//  SuiEndpointFailover.swift
//  VultisigApp
//

import Foundation
import OSLog

/// Supplies the Sui RPC hosts to attempt, most-preferred first.
///
/// Kept behind a protocol so the *transport* can change without touching any
/// call site: when Sui's JSON-RPC is replaced, only the host list and the
/// request bodies move — the failover walk, the retry policy and every caller
/// stay as they are.
protocol SuiEndpointProviding: Sendable {
    /// Hosts in attempt order. Never empty.
    func hosts() -> [URL]
}

/// Resolves the Sui host list from the user's custom-RPC override, falling back
/// to the built-in ordered list.
///
/// A configured override collapses the list to that single host on purpose. The
/// user picked a node; quietly failing over to a public one would both defeat
/// that choice and send their addresses to an operator they did not select.
struct SuiEndpointResolver: SuiEndpointProviding {
    private let resolver: RPCEndpointResolving
    private let defaultHosts: [URL]

    init(
        resolver: RPCEndpointResolving = CustomRPCStore.shared,
        defaultHosts: [URL] = SuiAPI.defaultHosts
    ) {
        self.resolver = resolver
        // An empty list would make every request throw `noEndpointsConfigured`,
        // so fall back to the primary host rather than ship a dead transport.
        self.defaultHosts = defaultHosts.isEmpty ? [SuiAPI.defaultHost] : defaultHosts
    }

    func hosts() -> [URL] {
        if let raw = resolver.url(for: .sui), let parsed = URL(string: raw) {
            return [parsed]
        }
        return defaultHosts
    }
}

enum SuiEndpointFailoverError: Error, LocalizedError {
    case noEndpointsConfigured

    var errorDescription: String? {
        switch self {
        case .noEndpointsConfigured:
            return "No Sui RPC endpoint is configured"
        }
    }
}

/// Decides whether a failed attempt is worth repeating against the next host.
enum SuiFailoverPolicy {

    /// `true` when the failure is a property of the host or the connection, so a
    /// different host plausibly succeeds.
    ///
    /// Errors that would recur identically everywhere — a request we failed to
    /// build, or a request the node understood and rejected — are deliberately
    /// excluded. Replaying those wastes a round trip, sends signed material to
    /// another operator for no reason, and buries the meaningful first error
    /// under whatever the last host happened to say.
    static func shouldTryNextHost(after error: Error) -> Bool {
        guard let httpError = error as? HTTPError else {
            // A non-`HTTPError` reached us from outside the transport (only
            // `CancellationError` does today, and the caller handles that
            // first). Treat it as deterministic rather than guessing.
            return false
        }

        switch httpError {
        case .timeout, .networkError, .invalidSSLCertificate:
            return true
        case .invalidResponse, .noData, .decodingFailed:
            // The host answered with something that is not a Sui RPC response.
            // That is a property of this host, not of the request.
            return true
        case .statusCode(let code, _):
            // 5xx is the node or a proxy in front of it; 408/429 are explicit
            // "come back later" answers. Every other 4xx is about the request,
            // and would be rejected identically by the next host.
            return code >= 500 || code == 408 || code == 429
        case .invalidURL, .encodingFailed:
            // Built locally. Every host would fail the same way.
            return false
        }
    }
}

/// Posts Sui RPC requests, failing over across the hosts from `endpoints`.
///
/// Failover covers **transport** faults only — an unreachable host, a TLS
/// failure, a timeout, a 5xx, a response that will not decode. A refusal that
/// arrives *inside* a well-formed body (the JSON-RPC `error` member, which Sui
/// returns with HTTP 200) decodes successfully and is handed to the caller
/// untouched, so it is never replayed against the remaining hosts: the node
/// already answered, and every other node would answer the same.
///
/// Failing a **broadcast** over to another host is safe. Sui identifies a
/// transaction by the digest of its signed bytes, so re-submitting identical
/// bytes is idempotent — the node returns the existing effects rather than
/// executing twice. That makes failover most valuable exactly where it would be
/// riskiest on a nonce-based chain: a broadcast whose response was lost in
/// transit still lands.
struct SuiFailoverClient {
    private let httpClient: HTTPClientProtocol
    private let endpoints: SuiEndpointProviding
    private let logger: Logger

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        endpoints: SuiEndpointProviding = SuiEndpointResolver(),
        logger: Logger = Log.chain.service
    ) {
        self.httpClient = httpClient
        self.endpoints = endpoints
        self.logger = logger
    }

    /// Builds a target per host with `makeTarget` and returns the first decoded
    /// response. Throws the last retryable failure when every host fails, or
    /// rethrows immediately on a failure no other host would survive.
    ///
    /// `shouldTryNextHost` lets a caller treat a *successfully decoded* response
    /// as a host-local miss and keep walking — the transaction-status poller
    /// needs this, because a digest broadcast through the fallback host is
    /// legitimately absent from the primary. When every host misses, the last
    /// decoded response is returned so the caller still sees a real answer.
    func request<T: Decodable>(
        responseType: T.Type,
        shouldTryNextHost: (T) -> Bool = { _ in false },
        makeTarget: (URL) -> TargetType
    ) async throws -> T {
        var lastFailure: Error?
        var lastMiss: T?

        for host in endpoints.hosts() {
            do {
                let decoded = try await httpClient.request(makeTarget(host), responseType: responseType).data
                guard shouldTryNextHost(decoded) else { return decoded }
                lastMiss = decoded
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                guard SuiFailoverPolicy.shouldTryNextHost(after: error) else { throw error }
                logger.warning(
                    "Sui RPC host \(host.absoluteString, privacy: .public) failed, trying the next: \(error.localizedDescription, privacy: .public)"
                )
                lastFailure = error
            }
        }

        if let lastMiss { return lastMiss }
        throw lastFailure ?? SuiEndpointFailoverError.noEndpointsConfigured
    }

    /// Convenience for the common shape: one `SuiAPI` endpoint, one host list.
    func request<T: Decodable>(
        _ endpoint: SuiAPI.Endpoint,
        responseType: T.Type
    ) async throws -> T {
        try await request(responseType: responseType) { host in
            SuiAPI(baseURL: host, endpoint: endpoint)
        }
    }
}
