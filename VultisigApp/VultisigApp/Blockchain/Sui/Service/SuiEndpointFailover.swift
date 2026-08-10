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
        defaultHosts: [URL] = SuiGraphQLAPI.defaultHosts
    ) {
        self.resolver = resolver
        // An empty list would make every request throw `noEndpointsConfigured`,
        // so fall back to the primary host rather than ship a dead transport.
        self.defaultHosts = defaultHosts.isEmpty ? [SuiGraphQLAPI.defaultHost] : defaultHosts
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

    /// Status codes that say the *request* is wrong rather than the host. Every
    /// host would reject these identically, so replaying them wastes a round
    /// trip, re-sends signed material to another operator for nothing, and
    /// buries the meaningful first error under whatever the last host said.
    ///
    /// Note what is deliberately absent: 401, 403 and 404 are host policy or
    /// capability (a node behind an API key, a proxy that does not serve this
    /// path), not request defects — and 404 in particular must fail over, or the
    /// transaction-status poller stops at the first host that has not seen a
    /// digest the fallback host broadcast.
    private static let requestFaultStatusCodes: Set<Int> = [400, 413, 414, 422, 431]

    /// `true` when the failure is a property of the host or the connection, so a
    /// different host plausibly succeeds.
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
            return !requestFaultStatusCodes.contains(code)
        case .invalidURL, .encodingFailed:
            // Built locally. Every host would fail the same way.
            return false
        }
    }
}

/// Posts Sui GraphQL requests, failing over across the hosts from `endpoints`.
///
/// Failover covers **transport** faults only — an unreachable host, a TLS
/// failure, a timeout, a 5xx, a response that will not decode. A refusal that
/// arrives *inside* a well-formed body (the GraphQL `errors` array, which Sui
/// returns with HTTP 200) decodes successfully and is the node's considered
/// verdict, so it is raised rather than replayed against the remaining hosts:
/// every other node would answer the same. The exception is the small set of
/// codes that mean "ask again" — see `SuiGraphQLError.retryableCodes`.
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
    /// legitimately absent from the primary.
    ///
    /// The last miss is returned only when **every** host answered and missed.
    /// If any host failed to answer at all, its failure is thrown instead: "not
    /// here" from one host and silence from another is not the same evidence as
    /// "not here" from all of them, and reporting it as such would let a partial
    /// outage masquerade as a verdict.
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

        if let lastFailure { throw lastFailure }
        if let lastMiss { return lastMiss }
        throw SuiEndpointFailoverError.noEndpointsConfigured
    }

    /// Runs a GraphQL document and returns its decoded `data`.
    ///
    /// The GraphQL half of the contract lives here rather than at each call site:
    /// a populated `errors` array is the node's considered answer and is raised,
    /// except for the small set of codes that mean "ask again", which fail over
    /// to the next host; an envelope with neither `data` nor `errors` is
    /// malformed; and an envelope carrying `jsonrpc` means the configured host
    /// still speaks the retired protocol, which is worth its own message because
    /// only a custom RPC override can produce it.
    ///
    /// `shouldTryNextHost` additionally lets a caller treat a successfully
    /// decoded payload as a host-local miss — the transaction-status poller uses
    /// it, because a digest broadcast through one host is legitimately absent
    /// from another, and a pruned node can miss a digest its peer already has.
    func query<T: Decodable>(
        _ document: String,
        variables: [String: Any] = [:],
        // swiftlint:disable:next unused_parameter
        responseType: T.Type,
        shouldTryNextHost: @escaping (T) -> Bool = { _ in false }
    ) async throws -> T {
        let envelope = try await request(
            responseType: SuiGraphQLResponse<T>.self,
            shouldTryNextHost: { envelope in
                if envelope.isRetryableNodeError { return true }
                guard let data = envelope.data, !envelope.hasErrors else { return false }
                return shouldTryNextHost(data)
            },
            makeTarget: { host in
                SuiGraphQLAPI(baseURL: host, document: document, variables: variables)
            }
        )

        if envelope.hasErrors {
            let errors = envelope.errors ?? []
            let message = errors.compactMap(\.message).joined(separator: "; ")
            throw SuiRPCError.node(
                message: message.isEmpty ? "unknown error" : message,
                code: errors.compactMap { $0.extensions?.code }.first
            )
        }

        if let data = envelope.data { return data }

        if envelope.jsonrpc != nil {
            let host = endpoints.hosts().last ?? SuiGraphQLAPI.defaultHost
            throw SuiRPCError.legacyJSONRPCEndpoint(host: host.absoluteString)
        }

        throw SuiRPCError.malformedResponse
    }
}
