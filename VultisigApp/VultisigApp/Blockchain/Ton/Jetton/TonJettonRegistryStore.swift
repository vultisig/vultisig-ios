//
//  TonJettonRegistryStore.swift
//  VultisigApp
//

import Foundation

/// Owns the verified-jetton registry: our curated TON tokens merged with
/// Tonkeeper's `ton-assets` whitelist, refreshed periodically.
///
/// Only a successful fetch is cached. Caching a failure would pin the degraded
/// registry for the whole TTL, so an outage would decide which jettons a wallet
/// recognises long after the outage ended; instead the next caller retries and
/// this one is served the curated list alone.
actor TonJettonRegistryStore {
    static let shared = TonJettonRegistryStore()

    private let httpClient: HTTPClientProtocol
    private let api: TonAssetsAPI
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date
    private let curatedJettons: [VerifiedJetton]
    private let logger = Log.chain.service

    private var cached: (registry: TonJettonRegistry, fetchedAt: Date)?
    /// Non-throwing on purpose: the failure is handled where it happens, and a
    /// waiting caller only needs to know whether a fresh registry arrived.
    private var inFlight: Task<TonJettonRegistry?, Never>?

    private lazy var curatedRegistry = TonJettonRegistry(curatedJettons)

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        api: TonAssetsAPI = TonAssetsAPI(),
        ttl: TimeInterval = 3600,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.httpClient = httpClient
        self.api = api
        self.ttl = ttl
        self.now = now
        self.curatedJettons = BundledTokensProvider
            .curatedTokens(for: .ton, defaults: defaults)
            .compactMap { VerifiedJetton(curated: $0) }
    }

    /// The registry, degrading to the curated list alone when the whitelist
    /// cannot be fetched — discovery and classification keep working offline,
    /// recognising fewer jettons. Never throws: an unreachable whitelist must
    /// not stop a wallet from discovering the jettons we curate ourselves.
    ///
    /// Concurrent callers share one fetch. Discovery runs per chain-detail
    /// refresh and those fan out several times after a swap, so without
    /// coalescing one screen would pull the whole list repeatedly.
    func registry() async -> TonJettonRegistry {
        if let cached, now().timeIntervalSince(cached.fetchedAt) < ttl {
            return cached.registry
        }

        let task = inFlight ?? Task { await self.loadMerged() }
        inFlight = task

        return await task.value ?? curatedRegistry
    }

    /// Fetch + merge, or `nil` when the whitelist could not be read. `cached` is
    /// written only on the success path; `inFlight` is cleared either way, so a
    /// failure is retried by the next caller rather than replayed out of a
    /// finished task for the rest of the TTL.
    private func loadMerged() async -> TonJettonRegistry? {
        defer { inFlight = nil }

        do {
            let response = try await httpClient.request(api, responseType: [TonAssetsJetton].self)
            let whitelisted = response.data.compactMap { VerifiedJetton(whitelisted: $0) }
            let registry = TonJettonRegistry(curatedJettons + whitelisted)

            cached = (registry, now())
            return registry
        } catch {
            logger.warning("ton-assets whitelist unavailable, using curated jettons only: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
