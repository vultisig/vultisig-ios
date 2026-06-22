//
//  CustomRPCStore.swift
//  VultisigApp
//

import Foundation
import OSLog
import SwiftData

/// App-wide store for custom RPC endpoint overrides.
///
/// Persistence is split into two layers on purpose:
///
/// - **Source of truth**: the `CustomRPCOverride` `@Model` rows in SwiftData.
///   These can only be read/written on the MainActor.
/// - **In-memory mirror**: a thread-safe `[chainRaw: url]` dictionary guarded by
///   an `NSLock`. The networking layer resolves RPC URLs OFF the main actor
///   (balance / fee / broadcast all run on background tasks), where reading a
///   `@Model` would violate the SwiftData-on-MainActor rule. `url(for:)` reads
///   the mirror synchronously from any thread, so the funnel never touches
///   SwiftData.
///
/// Writes go MainActor-only (`set` / `reset`): they update the `@Model` via the
/// `ModelContext` and then refresh the mirror. `reloadFromStore` hydrates the
/// mirror from the persisted rows at app launch so overrides survive relaunch.
final class CustomRPCStore: @unchecked Sendable {

    static let shared = CustomRPCStore()

    private let lock = NSLock()
    private var mirror: [String: String] = [:]
    private let logger = Logger(subsystem: "com.vultisig.app", category: "custom-rpc-store")

    private init() {}

    // MARK: - Read path (any thread, no SwiftData)

    /// Returns the user's custom RPC URL for `chain`, or `nil` when no override
    /// is set (caller falls back to its hardcoded default). Synchronous and
    /// lock-guarded — safe to call from any thread or background task. This is
    /// the ONLY read path used by the networking layer.
    func url(for chain: Chain) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return mirror[storageKey(for: chain)]
    }

    // MARK: - Write path (MainActor + SwiftData)

    /// Persists a custom RPC `url` for `chain` and refreshes the mirror.
    @MainActor
    func set(_ url: String, for chain: Chain) {
        guard let context = Storage.shared.modelContext else {
            logger.error("Cannot set custom RPC: model context unavailable")
            return
        }

        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let chainRaw = storageKey(for: chain)

        do {
            let descriptor = FetchDescriptor<CustomRPCOverride>(
                predicate: #Predicate { $0.chainRaw == chainRaw }
            )
            if let existing = try context.fetch(descriptor).first {
                existing.url = trimmed
            } else {
                context.insert(CustomRPCOverride(chainRaw: chainRaw, url: trimmed))
            }
            try context.save()
            updateMirror(chainRaw: chainRaw, url: trimmed)
        } catch {
            logger.error("Failed to persist custom RPC for \(chainRaw): \(error.localizedDescription)")
        }
    }

    /// Removes any custom RPC override for `chain` and refreshes the mirror so
    /// the funnel falls back to the hardcoded default.
    @MainActor
    func reset(_ chain: Chain) {
        guard let context = Storage.shared.modelContext else {
            logger.error("Cannot reset custom RPC: model context unavailable")
            return
        }

        let chainRaw = storageKey(for: chain)

        do {
            let descriptor = FetchDescriptor<CustomRPCOverride>(
                predicate: #Predicate { $0.chainRaw == chainRaw }
            )
            for override in try context.fetch(descriptor) {
                context.delete(override)
            }
            try context.save()
            updateMirror(chainRaw: chainRaw, url: nil)
        } catch {
            logger.error("Failed to reset custom RPC for \(chainRaw): \(error.localizedDescription)")
        }
    }

    /// Hydrates the in-memory mirror from the persisted `@Model` rows. Call once
    /// at app launch so overrides survive relaunch.
    @MainActor
    func reloadFromStore() {
        guard let context = Storage.shared.modelContext else {
            logger.error("Cannot reload custom RPC overrides: model context unavailable")
            return
        }

        do {
            var overrides = try context.fetch(FetchDescriptor<CustomRPCOverride>())
            migrateLegacyPolygonV2(in: &overrides, context: context)
            let snapshot = Dictionary(
                overrides.map { ($0.chainRaw, $0.url) },
                uniquingKeysWith: { _, last in last }
            )
            lock.lock()
            mirror = snapshot
            lock.unlock()
            logger.info("Loaded \(snapshot.count) custom RPC override(s)")
        } catch {
            logger.error("Failed to load custom RPC overrides: \(error.localizedDescription)")
        }
    }

    // MARK: - Migration

    /// Folds any legacy `polygonV2`-keyed override onto the canonical `polygon`
    /// key and deletes the orphaned row. Earlier builds keyed overrides by the
    /// enum case name, so a Polygon override could land under either case; both
    /// chains now resolve through `storageKey(for:)` to the `polygon` key, and a
    /// stale `polygonV2` row would otherwise be unreachable (and could collide
    /// with the `.unique` constraint). When both rows exist, `polygon` wins.
    @MainActor
    private func migrateLegacyPolygonV2(in overrides: inout [CustomRPCOverride], context: ModelContext) {
        let legacyKey = Chain.polygonV2.rawValue
        guard let legacyIndex = overrides.firstIndex(where: { $0.chainRaw == legacyKey }) else {
            return
        }

        let canonicalKey = Chain.polygon.rawValue
        let legacy = overrides[legacyIndex]
        if !overrides.contains(where: { $0.chainRaw == canonicalKey }) {
            context.insert(CustomRPCOverride(chainRaw: canonicalKey, url: legacy.url))
        }
        context.delete(legacy)
        overrides.remove(at: legacyIndex)

        do {
            try context.save()
            overrides = try context.fetch(FetchDescriptor<CustomRPCOverride>())
        } catch {
            logger.error("Failed to migrate legacy polygonV2 override: \(error.localizedDescription)")
        }
    }

    // MARK: - Mirror helpers

    private func updateMirror(chainRaw: String, url: String?) {
        lock.lock()
        defer { lock.unlock() }
        if let url, !url.isEmpty {
            mirror[chainRaw] = url
        } else {
            mirror.removeValue(forKey: chainRaw)
        }
    }

    /// Normalizes a chain to the single persistence key used for its override.
    /// `.polygon` and `.polygonV2` are the same network (chainId 137, shown once
    /// in the picker), so both share one override slot keyed by `.polygon`.
    private func storageKey(for chain: Chain) -> String {
        switch chain {
        case .polygonV2:
            return Chain.polygon.rawValue
        default:
            return chain.rawValue
        }
    }
}
