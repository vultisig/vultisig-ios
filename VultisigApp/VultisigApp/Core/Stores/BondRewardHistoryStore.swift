//
//  BondRewardHistoryStore.swift
//  VultisigApp
//

import Foundation

/// Per-device copy of the bond rewards already realized, so a past churn is
/// read from the network once. Nodes keep only recent state, so this copy is
/// also the only source for churns they have since dropped.
///
/// At most `BondRewardHistoryConfig.limit` rows (about 40 bytes each) per bond
/// provider and node, in `UserDefaults`.
struct BondRewardHistoryStore {
    private static let writeLock = NSLock()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Runs `load` with the rewards already saved for this bond provider on
    /// this node, saves the rewards it returns, and returns its result.
    func fetch(
        bondAddress: String,
        nodeAddress: String,
        using load: ([Int: BondRewardHistoryEntry]) async throws -> BondRewardHistory
    ) async throws -> BondRewardHistory {
        let key = "bondRewardHistory.\(bondAddress).\(nodeAddress)"
        let history = try await load(read(key))
        write(key, adding: history.entries)
        return history
    }

    private func read(_ key: String) -> [Int: BondRewardHistoryEntry] {
        guard
            let data = defaults.data(forKey: key),
            let entries = try? JSONDecoder().decode([BondRewardHistoryEntry].self, from: data)
        else { return [:] }
        return Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Merges into what is stored now, not what `load` started from: the card and the
    /// sheet fetch the same key at once, and each must keep the other's rows.
    private func write(_ key: String, adding entries: [BondRewardHistoryEntry]) {
        Self.writeLock.lock()
        defer { Self.writeLock.unlock() }

        let saved = read(key)
        var merged = saved
        for entry in entries where merged[entry.id] == nil {
            merged[entry.id] = entry
        }
        guard merged.count > saved.count else { return }

        let newest = merged.values
            .sorted { $0.id > $1.id }
            .prefix(BondRewardHistoryConfig.limit)
        if let data = try? JSONEncoder().encode(Array(newest)) {
            defaults.set(data, forKey: key)
        }
    }
}
