//
//  WidgetSharedStorage.swift
//  VultisigApp
//
//  Constants shared by the application and WidgetKit extension. Keep this
//  file Foundation-only so both targets can compile it without importing the
//  application's service or model graphs.
//

import Foundation

enum WidgetSharedStorage {
    static let appGroupIdentifier = "group.com.vultisig.wallet"
    static let currencyKey = "marketWidgets.currency"
    static let watchlistKey = "marketWidgets.watchlist"
    static let watchlistWidgetKind = "com.vultisig.widget.crypto-watchlist"
    static let maximumWatchlistAssets = 5

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static var currencyCode: String {
        defaults?.string(forKey: currencyKey) ?? "USD"
    }

    static func setCurrencyCode(_ value: String) {
        defaults?.set(value.uppercased(), forKey: currencyKey)
    }

    static func watchlistAssets(
        in defaults: UserDefaults? = WidgetSharedStorage.defaults
    ) -> [WidgetWatchlistAsset] {
        guard let data = defaults?.data(forKey: watchlistKey),
              let assets = try? JSONDecoder().decode([WidgetWatchlistAsset].self, from: data) else {
            return []
        }
        return normalizedWatchlist(assets)
    }

    static func hasStoredWatchlist(
        in defaults: UserDefaults? = WidgetSharedStorage.defaults
    ) -> Bool {
        defaults?.object(forKey: watchlistKey) != nil
    }

    static func setWatchlistAssets(
        _ assets: [WidgetWatchlistAsset],
        in defaults: UserDefaults? = WidgetSharedStorage.defaults
    ) {
        guard let defaults,
              let data = try? JSONEncoder().encode(normalizedWatchlist(assets)) else {
            return
        }
        defaults.set(data, forKey: watchlistKey)
    }

    private static func normalizedWatchlist(_ assets: [WidgetWatchlistAsset]) -> [WidgetWatchlistAsset] {
        assets.reduce(into: [WidgetWatchlistAsset]()) { result, asset in
            let normalized = WidgetWatchlistAsset(
                id: asset.id,
                symbol: asset.symbol,
                name: asset.name,
                imageURL: asset.imageURL
            )
            guard !normalized.id.isEmpty,
                  !result.contains(where: { $0.id == normalized.id }) else {
                return
            }
            result.append(normalized)
        }
        .prefix(maximumWatchlistAssets)
        .map { $0 }
    }
}

struct WidgetWatchlistAsset: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let symbol: String
    let name: String
    let imageURL: URL?

    init(id: String, symbol: String, name: String, imageURL: URL?) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.imageURL = imageURL
    }

    init(_ asset: WidgetMarketAsset) {
        self.init(
            id: asset.id,
            symbol: asset.symbol,
            name: asset.name,
            imageURL: asset.imageURL
        )
    }

    var iconLogo: String {
        if let imageURL {
            return imageURL.absoluteString
        }

        switch id {
        case "bitcoin": return "btc"
        case "ethereum": return "eth"
        case "tether": return "usdt"
        case "binancecoin": return "bsc"
        case "solana": return "solana"
        default: return ""
        }
    }
}
