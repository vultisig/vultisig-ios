//
//  WidgetMarketAsset.swift
//  VultisigApp
//

import Foundation

struct WidgetMarketAsset: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let symbol: String
    let name: String
    let imageURL: URL?
    let iconData: Data?
    let currentPrice: Double
    let priceChangePercentage24h: Double?
    let marketCapRank: Int?
    let sparkline: [Double]

    var iconLogo: String {
        Self.localIconLogo(for: id)
    }

    static func localIconLogo(for id: String) -> String {
        switch id {
        case "bitcoin":
            return "btc"
        case "ethereum":
            return "eth"
        case "tether":
            return "usdt"
        case "binancecoin":
            return "bsc"
        case "solana":
            return "solana"
        default:
            return ""
        }
    }

    func withIconData(_ data: Data?) -> WidgetMarketAsset {
        WidgetMarketAsset(
            id: id,
            symbol: symbol,
            name: name,
            imageURL: imageURL,
            iconData: data,
            currentPrice: currentPrice,
            priceChangePercentage24h: priceChangePercentage24h,
            marketCapRank: marketCapRank,
            sparkline: sparkline
        )
    }
}

struct WidgetMarketResult: Equatable, Sendable {
    let assets: [WidgetMarketAsset]
    let updatedAt: Date
    let isStale: Bool
}

enum WidgetMarketQuery: Hashable, Sendable {
    case top(limit: Int)
    case catalog(limit: Int)
    case ids([String])

    var normalizedIDs: [String] {
        guard case .ids(let ids) = self else { return [] }
        let normalized = ids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let unique = normalized.reduce(into: [String]()) { result, id in
            if !result.contains(id) {
                result.append(id)
            }
        }
        return Array(unique.prefix(5))
    }

    var limit: Int {
        switch self {
        case .top(let limit):
            return min(5, max(1, limit))
        case .catalog(let limit):
            return min(50, max(1, limit))
        case .ids:
            return min(5, max(1, normalizedIDs.count))
        }
    }

    var includesSparkline: Bool {
        guard case .catalog = self else { return true }
        return false
    }

    var cacheKey: String {
        switch self {
        case .top:
            return "top-\(limit)"
        case .catalog:
            return "catalog-\(limit)"
        case .ids:
            return "ids-\(normalizedIDs.joined(separator: ","))"
        }
    }
}
