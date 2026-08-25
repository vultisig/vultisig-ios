//
//  SwapKitTokensCache.swift
//  VultisigApp
//
//  Main-actor token-provider facade over the shared SwapKit asset catalogue.
//

import Foundation

@MainActor
final class SwapKitTokensCache: DestinationTokenProvider {
    static let shared = SwapKitTokensCache(catalog: .shared)

    let kind: String = "swapKit"
    let verification: TokenVerification = .unverified

    private let catalog: SwapKitAssetCatalog

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        providerCache: SwapKitProviderCache = .shared,
        catalog: SwapKitAssetCatalog? = nil
    ) {
        self.catalog = catalog ?? SwapKitAssetCatalog(
            httpClient: httpClient,
            providerCache: providerCache
        )
    }

    func tokens(
        for chain: Chain,
        forceRefresh: Bool
    ) async -> DestinationTokenBucket {
        await catalog.tokens(for: chain, forceRefresh: forceRefresh)
    }

    func tokens(
        for chain: Chain,
        forceRefresh: Bool = false,
        now: Date
    ) async -> DestinationTokenBucket {
        await catalog.tokens(
            for: chain,
            forceRefresh: forceRefresh,
            now: now
        )
    }

    func setSnapshot(
        buckets: [Chain: DestinationTokenBucket],
        fetchedAt: Date = Date()
    ) async {
        await catalog.setSnapshot(
            SwapKitAssetCatalogSnapshot(
                buckets: buckets,
                identifiers: [:]
            ),
            fetchedAt: fetchedAt
        )
    }

    func clearCache() {
        Task {
            await catalog.clearCache()
        }
    }

    nonisolated static func mergeByChain(
        responses: [SwapKitTokensResponse]
    ) -> [Chain: DestinationTokenBucket] {
        SwapKitAssetCatalog.buildSnapshot(responses: responses).buckets
    }
}
