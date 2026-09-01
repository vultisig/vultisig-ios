//
//  WidgetMarketService.swift
//  VultisigApp
//

import Foundation

actor WidgetMarketService {
    private let remote: any WidgetMarketRemote
    private let cache: WidgetMarketCache
    private let now: @Sendable () -> Date

    init(
        remote: any WidgetMarketRemote = WidgetMarketClient(),
        cache: WidgetMarketCache = WidgetMarketCache(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.remote = remote
        self.cache = cache
        self.now = now
    }

    func cachedResult(query: WidgetMarketQuery, currency: String) async -> WidgetMarketResult? {
        guard let cached = await cache.entry(for: cacheKey(query: query, currency: currency)) else {
            return nil
        }
        return WidgetMarketResult(
            assets: cached.assets,
            updatedAt: cached.updatedAt,
            isStale: true
        )
    }

    func load(
        query: WidgetMarketQuery,
        currency: String,
        downloadsIcons: Bool = true
    ) async throws -> WidgetMarketResult {
        let key = cacheKey(query: query, currency: currency)
        let cached = await cache.entry(for: key)

        do {
            let remoteAssets = try await remote.markets(query: query, currency: currency)
            let assets: [WidgetMarketAsset]
            if downloadsIcons {
                assets = await addingIcons(to: remoteAssets, cached: cached?.assets ?? [])
            } else {
                assets = remoteAssets
            }
            let updatedAt = now()
            try? await cache.store(assets, updatedAt: updatedAt, for: key)
            return WidgetMarketResult(assets: assets, updatedAt: updatedAt, isStale: false)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch {
            guard let cached else { throw error }
            return WidgetMarketResult(assets: cached.assets, updatedAt: cached.updatedAt, isStale: true)
        }
    }

    private func cacheKey(query: WidgetMarketQuery, currency: String) -> String {
        "\(currency.lowercased())-\(query.cacheKey)"
    }

    private func addingIcons(
        to assets: [WidgetMarketAsset],
        cached: [WidgetMarketAsset]
    ) async -> [WidgetMarketAsset] {
        let cachedAssets = Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0) })

        let downloadedIcons = await withTaskGroup(
            of: (String, Data?).self,
            returning: [String: Data].self
        ) { group in
            for asset in assets where shouldDownloadIcon(for: asset, cachedAssets: cachedAssets) {
                group.addTask { [remote] in
                    guard let imageURL = asset.imageURL else { return (asset.id, nil) }
                    return (asset.id, try? await remote.iconData(from: imageURL))
                }
            }

            var icons: [String: Data] = [:]
            for await (id, data) in group {
                icons[id] = data
            }
            return icons
        }

        return assets.map { asset in
            asset.withIconData(downloadedIcons[asset.id] ?? cachedAssets[asset.id]?.iconData)
        }
    }

    private func shouldDownloadIcon(
        for asset: WidgetMarketAsset,
        cachedAssets: [String: WidgetMarketAsset]
    ) -> Bool {
        guard asset.imageURL != nil else { return false }
        guard let cached = cachedAssets[asset.id] else { return true }
        return cached.iconData == nil || cached.imageURL != asset.imageURL
    }
}
