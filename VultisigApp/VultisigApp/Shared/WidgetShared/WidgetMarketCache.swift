//
//  WidgetMarketCache.swift
//  VultisigApp
//

import Foundation

struct WidgetMarketCacheEntry: Codable, Equatable, Sendable {
    let assets: [WidgetMarketAsset]
    let updatedAt: Date
}

actor WidgetMarketCache {
    private static let maximumEntryCount = 6

    private let fileURL: URL?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = WidgetMarketCache.defaultFileURL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func entry(for key: String) -> WidgetMarketCacheEntry? {
        loadEntries()[key]
    }

    func store(_ assets: [WidgetMarketAsset], updatedAt: Date, for key: String) throws {
        guard let fileURL else { return }
        var entries = loadEntries()
        entries[key] = WidgetMarketCacheEntry(assets: assets, updatedAt: updatedAt)
        while entries.count > Self.maximumEntryCount,
              let oldestKey = entries.min(by: { $0.value.updatedAt < $1.value.updatedAt })?.key {
            entries.removeValue(forKey: oldestKey)
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    private func loadEntries() -> [String: WidgetMarketCacheEntry] {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let entries = try? decoder.decode([String: WidgetMarketCacheEntry].self, from: data) else {
            return [:]
        }
        return entries
    }

    private static var defaultFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSharedStorage.appGroupIdentifier)?
            .appendingPathComponent("MarketWidgets", isDirectory: true)
            .appendingPathComponent("market-cache.json", isDirectory: false)
    }
}
