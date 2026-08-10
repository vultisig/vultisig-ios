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
    /// response. Throws the last transport failure when every host fails.
    func request<T: Decodable>(
        responseType: T.Type,
        makeTarget: (URL) -> TargetType
    ) async throws -> T {
        var lastTransportFailure: Error?

        for host in endpoints.hosts() {
            do {
                return try await httpClient.request(makeTarget(host), responseType: responseType).data
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logger.warning(
                    "Sui RPC host \(host.absoluteString, privacy: .public) failed, trying the next: \(error.localizedDescription, privacy: .public)"
                )
                lastTransportFailure = error
            }
        }

        throw lastTransportFailure ?? SuiEndpointFailoverError.noEndpointsConfigured
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
