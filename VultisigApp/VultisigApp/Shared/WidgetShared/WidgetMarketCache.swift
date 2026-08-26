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
        loadEntries(from: fileURL)[key]
    }

    func store(_ assets: [WidgetMarketAsset], updatedAt: Date, for key: String) throws {
        guard let fileURL else { return }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(
            writingItemAt: fileURL,
            options: .forMerging,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                var entries = loadEntries(from: coordinatedURL)
                entries[key] = WidgetMarketCacheEntry(assets: assets, updatedAt: updatedAt)
                while entries.count > Self.maximumEntryCount,
                      let oldestKey = entries.min(by: {
                          $0.value.updatedAt < $1.value.updatedAt
                      })?.key {
                    entries.removeValue(forKey: oldestKey)
                }
                let data = try encoder.encode(entries)
                try data.write(to: coordinatedURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let writeError {
            throw writeError
        }
    }

    private func loadEntries(from fileURL: URL?) -> [String: WidgetMarketCacheEntry] {
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
