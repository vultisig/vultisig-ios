//
//  LocalWidgetWatchlistCatalog.swift
//  VultisigApp
//

import Foundation

enum LocalWidgetWatchlistCatalog {
    static var assets: [WidgetWatchlistAsset] {
        assets(from: TokensStore.TokenSelectionAssets)
    }

    static func assets(from metas: [CoinMeta]) -> [WidgetWatchlistAsset] {
        metas.reduce(into: [WidgetWatchlistAsset]()) { result, meta in
            guard let asset = asset(from: meta),
                  !result.contains(where: { $0.id == asset.id }) else {
                return
            }
            result.append(asset)
        }
    }

    private static func asset(from meta: CoinMeta) -> WidgetWatchlistAsset? {
        let id = meta.priceProviderId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !id.isEmpty, meta.chain.isProductionWidgetWatchlistChain else { return nil }

        return WidgetWatchlistAsset(
            id: id,
            symbol: meta.ticker,
            name: displayName(for: meta),
            imageURL: nil
        )
    }

    private static func displayName(for meta: CoinMeta) -> String {
        if meta.isNativeToken {
            return meta.chain.name
        }
        return meta.ticker
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
