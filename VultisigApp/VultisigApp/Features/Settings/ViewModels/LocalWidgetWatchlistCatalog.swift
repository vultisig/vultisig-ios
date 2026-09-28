//
//  LocalWidgetWatchlistCatalog.swift
//  VultisigApp
//

import Foundation

enum LocalWidgetWatchlistCatalog {
    private static let defaultEntries = entries(from: TokensStore.TokenSelectionAssets)
    private static let defaultLogoByID = Dictionary(
        uniqueKeysWithValues: defaultEntries.map { ($0.asset.id, $0.logo) }
    )

    static var assets: [WidgetWatchlistAsset] {
        defaultEntries.map(\.asset)
    }

    static func assets(from metas: [CoinMeta]) -> [WidgetWatchlistAsset] {
        entries(from: metas).map(\.asset)
    }

    static func logo(for id: String) -> String? {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return defaultLogoByID[normalizedID]
    }

    static func logo(for id: String, in metas: [CoinMeta]) -> String? {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return Dictionary(uniqueKeysWithValues: entries(from: metas).map { ($0.asset.id, $0.logo) })[normalizedID]
    }

    private static func entries(from metas: [CoinMeta]) -> [Entry] {
        var seenIDs = Set<String>()
        return metas.reduce(into: [Entry]()) { result, meta in
            guard let entry = entry(from: meta), seenIDs.insert(entry.asset.id).inserted else {
                return
            }
            result.append(entry)
        }
    }

    private static func entry(from meta: CoinMeta) -> Entry? {
        let id = meta.priceProviderId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !id.isEmpty, meta.chain.isProductionWidgetWatchlistChain else { return nil }

        return Entry(
            asset: WidgetWatchlistAsset(
                id: id,
                symbol: meta.ticker,
                name: displayName(for: meta),
                imageURL: nil
            ),
            logo: meta.logo
        )
    }

    private static func displayName(for meta: CoinMeta) -> String {
        if meta.isNativeToken {
            return meta.chain.name
        }
        return meta.ticker
    }

    private struct Entry {
        let asset: WidgetWatchlistAsset
        let logo: String
    }
}

private extension Chain {
    var isProductionWidgetWatchlistChain: Bool {
        switch self {
        case .ethereumSepolia, .thorChainChainnet, .thorChainStagenet:
            return false
        default:
            return true
        }
    }
}
