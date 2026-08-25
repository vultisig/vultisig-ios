//
//  SwapKitAssetCatalog.swift
//  VultisigApp
//
//  Shared SwapKit token-catalog cache. The picker consumes its CoinMeta
//  buckets while the quote path consumes the exact upstream identifiers.
//

import Foundation
import OSLog

private let logger = Log.swap.store

struct SwapKitAssetKey: Hashable, Sendable {
    let chain: Chain
    let contractAddress: String

    init(chain: Chain, contractAddress: String, isNativeToken: Bool) {
        self.chain = chain
        if isNativeToken || contractAddress.isEmpty {
            self.contractAddress = ""
        } else if chain.chainType == .EVM {
            self.contractAddress = contractAddress.lowercased()
        } else {
            self.contractAddress = contractAddress
        }
    }

    init(coin: Coin) {
        self.init(
            chain: coin.chain,
            contractAddress: coin.contractAddress,
            isNativeToken: coin.isNativeToken
        )
    }

    init(coinMeta: CoinMeta) {
        self.init(
            chain: coinMeta.chain,
            contractAddress: coinMeta.contractAddress,
            isNativeToken: coinMeta.isNativeToken
        )
    }
}

struct SwapKitAssetCatalogSnapshot: Sendable {
    let buckets: [Chain: DestinationTokenBucket]
    let identifiers: [SwapKitAssetKey: Set<String>]
}

actor SwapKitAssetCatalog {
    static let shared = SwapKitAssetCatalog()

    private let httpClient: HTTPClientProtocol
    private let providerCache: SwapKitProviderCache
    private var snapshot: Snapshot?
    private var inFlight: Task<SwapKitAssetCatalogSnapshot?, Never>?

    private struct Snapshot: Sendable {
        let catalog: SwapKitAssetCatalogSnapshot
        let fetchedAt: Date
    }

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        providerCache: SwapKitProviderCache = .shared
    ) {
        self.httpClient = httpClient
        self.providerCache = providerCache
    }

    func tokens(
        for chain: Chain,
        forceRefresh: Bool = false,
        now: Date = Date()
    ) async -> DestinationTokenBucket {
        guard SwapKitConfig.isFeatureEnabled else {
            return .empty(chain: chain)
        }
        let catalog = await ensureSnapshot(now: now, forceRefresh: forceRefresh)
        return catalog?.buckets[chain] ?? .empty(chain: chain)
    }

    func identifier(
        for key: SwapKitAssetKey,
        forceRefresh: Bool = false,
        now: Date = Date()
    ) async -> String? {
        guard SwapKitConfig.isFeatureEnabled else { return nil }
        guard let identifiers = await ensureSnapshot(
            now: now,
            forceRefresh: forceRefresh
        )?.identifiers[key], identifiers.count == 1 else {
            return nil
        }
        return identifiers.first
    }

    func setSnapshot(
        _ catalog: SwapKitAssetCatalogSnapshot,
        fetchedAt: Date = Date()
    ) {
        snapshot = Snapshot(catalog: catalog, fetchedAt: fetchedAt)
    }

    func clearCache() {
        snapshot = nil
        inFlight?.cancel()
        inFlight = nil
    }

    private func ensureSnapshot(
        now: Date,
        forceRefresh: Bool
    ) async -> SwapKitAssetCatalogSnapshot? {
        if !forceRefresh,
           let snapshot,
           now.timeIntervalSince(snapshot.fetchedAt) < SwapKitConfig.tokensCacheTTL {
            return snapshot.catalog
        }
        if let inFlight {
            return await inFlight.value
        }

        let task = Task { [providerCache, httpClient] in
            await Self.fetchAll(
                providerCache: providerCache,
                httpClient: httpClient,
                now: now
            )
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        if let result {
            snapshot = Snapshot(catalog: result, fetchedAt: now)
        }
        return result ?? snapshot?.catalog
    }

    private static func fetchAll(
        providerCache: SwapKitProviderCache,
        httpClient: HTTPClientProtocol,
        now: Date
    ) async -> SwapKitAssetCatalogSnapshot? {
        guard let allProviders = await providerCache.providers(now: now) else {
            logger.info("[swapkit-tokens] no provider snapshot available — skipping fetch")
            return nil
        }

        let providerNames = Set(allProviders.map { $0.provider.uppercased() })
            .filter { !SwapKitConfig.filteredProviders.contains($0) }
            .sorted()
        guard !providerNames.isEmpty else {
            logger.info("[swapkit-tokens] no eligible providers after THORChain/Maya filter")
            return SwapKitAssetCatalogSnapshot(buckets: [:], identifiers: [:])
        }

        let fetched = await withTaskGroup(of: SwapKitTokensResponse?.self) { group in
            for name in providerNames {
                group.addTask {
                    await fetchTokens(provider: name, httpClient: httpClient)
                }
            }
            var collected: [SwapKitTokensResponse] = []
            for await response in group {
                if let response {
                    collected.append(response)
                }
            }
            return collected
        }
        return buildSnapshot(responses: fetched)
    }

    private static func fetchTokens(
        provider: String,
        httpClient: HTTPClientProtocol
    ) async -> SwapKitTokensResponse? {
        do {
            let response = try await httpClient.request(
                SwapKitAPI.tokens(provider: provider),
                responseType: SwapKitTokensResponse.self
            )
            return response.data
        } catch {
            logger.warning("[swapkit-tokens] failed to fetch \(provider, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    nonisolated static func buildSnapshot(
        responses: [SwapKitTokensResponse]
    ) -> SwapKitAssetCatalogSnapshot {
        var byChainTokens: [Chain: [CoinMeta]] = [:]
        var byChainIdentifiers: [Chain: Set<String>] = [:]
        var assetIdentifiers: [SwapKitAssetKey: Set<String>] = [:]

        for response in responses {
            for token in response.tokens {
                guard let coinMeta = token.toCoinMeta() else { continue }
                let key = SwapKitAssetKey(coinMeta: coinMeta)
                assetIdentifiers[key, default: []].insert(token.identifier)

                let chain = coinMeta.chain
                var seen = byChainIdentifiers[chain] ?? []
                guard !seen.contains(token.identifier) else { continue }
                seen.insert(token.identifier)
                byChainIdentifiers[chain] = seen
                byChainTokens[chain, default: []].append(coinMeta)
            }
        }

        var buckets: [Chain: DestinationTokenBucket] = [:]
        for (chain, tokens) in byChainTokens {
            buckets[chain] = DestinationTokenBucket(
                chain: chain,
                tokens: tokens,
                uniqueIds: Set(tokens.map(\.uniqueId))
            )
        }
        return SwapKitAssetCatalogSnapshot(
            buckets: buckets,
            identifiers: assetIdentifiers
        )
    }
}
