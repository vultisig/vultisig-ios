//
//  OneInchCatalogProvider.swift
//  VultisigApp
//
//  1inch `/tokens` per EVM chain as a `TokenCatalogProvider`. Emits per-token
//  verification: `.verified("CoinGecko")` when 1inch marks the token
//  CoinGecko-listed, else `.unverified` — the same legitimacy signal
//  `EvmCoinFinder` gates auto-discovery on. This is the fix for the historical
//  `OneInchToken.toCoinMeta` trust-signal drop: the picker path used to discard
//  it, so unverified 1inch tokens surfaced unbadged.
//
//  Freshness (TTL / coalescing / fail-open) is governed by `SwapTokenListCache`
//  at the `TokenSearchService.loadTokens` layer, so this provider stays thin:
//  fetch → tag → write-through the disk snapshot; on failure serve the last-good
//  disk snapshot (the offline floor beneath the in-memory cache).
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "oneinch-catalog-provider")

@MainActor
final class OneInchCatalogProvider: TokenCatalogProvider {
    static let shared = OneInchCatalogProvider()

    let kind = "oneinch"
    /// Above the default (0), below the curated bundle (`Int.max`) — curated
    /// metadata wins a collision, but 1inch outranks other unspecified sources.
    let precedence = 10
    // Per-token verification is applied in `catalogTokens`; this default is only
    // a fail-closed floor for the derived bucket path.
    let verification: TokenVerification = .unverified

    private let service: OneInchService
    private let disk: TokenCatalogDiskCache

    init(service: OneInchService = .shared, disk: TokenCatalogDiskCache = TokenCatalogDiskCache(namespace: "oneinch")) {
        self.service = service
        self.disk = disk
    }

    func tokens(for chain: Chain, forceRefresh: Bool) async -> DestinationTokenBucket {
        let catalog = await catalogTokens(for: chain, forceRefresh: forceRefresh)
        let metas = catalog.map(\.meta)
        return DestinationTokenBucket(chain: chain, tokens: metas, uniqueIds: Set(metas.map(\.uniqueId)))
    }

    func catalogTokens(for chain: Chain, forceRefresh _: Bool) async -> [CatalogToken] {
        guard service.isChainSupported(chain: chain), let chainID = chain.chainID else { return [] }
        let sourceKind = kind
        do {
            let tokens = try await service.fetchTokens(chain: chainID)
                .sorted(by: { $0.name < $1.name })
                .map { $0.toCatalogToken(chain: chain, sourceKind: sourceKind) }
            let cache = disk
            Task.detached(priority: .utility) { cache.save(tokens, chain: chain) }
            return tokens
        } catch is CancellationError {
            // The caller is tearing down — don't serve stale (it would be
            // discarded anyway) and skip the disk read. Mirrors SwapTokenListCache.
            return []
        } catch {
            logger.warning("[oneinch-catalog] fetch failed for \(chain.rawValue, privacy: .public), serving disk snapshot: \(String(describing: error), privacy: .public)")
            let cache = disk
            return await Task.detached(priority: .utility) { cache.load(chain: chain) }.value ?? []
        }
    }
}
