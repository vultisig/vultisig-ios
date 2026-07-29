//
//  JupiterCatalogProvider.swift
//  VultisigApp
//
//  Jupiter's Solana token list as a `TokenCatalogProvider`. The upstream
//  endpoint is pre-filtered server-side to `?query=verified`, so the whole list
//  carries implicit "Jupiter-verified" trust — every token is
//  `.verified("Jupiter")`.
//
//  The list is returned best-first, ranked by Jupiter's own `organicScore` (see
//  `SolanaJupiterToken.rankedForCatalog`). `CatalogToken` carries no rank field,
//  so order is the contract: a consumer showing only the head of the list — the
//  token picker's browse list — gets the tokens worth showing.
//
//  Like `OneInchCatalogProvider`, freshness is governed upstream by
//  `SwapTokenListCache`; this provider fetches → tags → write-throughs the disk
//  snapshot, and serves the last-good snapshot on failure (offline floor).
//

import Foundation
import OSLog

private let logger = Log.wallet.service

@MainActor
final class JupiterCatalogProvider: TokenCatalogProvider {
    static let shared = JupiterCatalogProvider()

    let kind = "jupiter"
    let precedence = 10
    let verification: TokenVerification = .verified(source: "Jupiter")

    private let service: SolanaService
    private let disk: TokenCatalogDiskCache

    init(service: SolanaService = .shared, disk: TokenCatalogDiskCache = TokenCatalogDiskCache(namespace: "jupiter")) {
        self.service = service
        self.disk = disk
    }

    func tokens(for chain: Chain, forceRefresh: Bool) async -> DestinationTokenBucket {
        let catalog = await catalogTokens(for: chain, forceRefresh: forceRefresh)
        let metas = catalog.map(\.meta)
        return DestinationTokenBucket(chain: chain, tokens: metas, uniqueIds: Set(metas.map(\.uniqueId)))
    }

    func catalogTokens(for chain: Chain, forceRefresh _: Bool) async -> [CatalogToken] {
        guard chain == .solana else { return [] }
        let sourceKind = kind
        let tokenVerification = verification
        do {
            let metas = try await service.fetchSolanaJupiterTokenList()
            let catalog = metas.map { CatalogToken(meta: $0, verification: tokenVerification, sourceKind: sourceKind) }
            let cache = disk
            Task.detached(priority: .utility) { cache.save(catalog, chain: chain) }
            return catalog
        } catch is CancellationError {
            return []
        } catch {
            logger.warning("[jupiter-catalog] fetch failed, serving disk snapshot: \(String(describing: error), privacy: .public)")
            let cache = disk
            return await Task.detached(priority: .utility) { cache.load(chain: chain) }.value ?? []
        }
    }
}
