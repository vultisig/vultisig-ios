//
//  TokenCatalogDiskCache.swift
//  VultisigApp
//
//  Per-chain, per-namespace on-disk snapshot of a network provider's last-good
//  `CatalogToken` list, so a cold offline launch has more than just the bundled
//  curated floor. A dynamic provider write-throughs on a successful fetch and
//  falls back to the snapshot when the network fails. In-memory TTL + coalescing
//  stays with `SwapTokenListCache` (the front cache); this is only the durable
//  offline floor beneath it.
//
//  TRUST: this is untrusted persistence living in the app's Caches sandbox (iOS
//  data protection). On load, verification is capped at `.verified` — a file can
//  never confer `.curated` (the tier reserved for the in-memory bundled provider
//  that wins dedup precedence). `.verified`/`.unverified` are preserved so a
//  provider's last-good verified list still surfaces during a transient outage,
//  instead of being filtered out and letting the outer cache overwrite a
//  complete list with a bundled-only one. Verification is never decoded from a
//  third-party source payload — providers assign it in code from a live signal
//  before it is ever written here.
//

import Foundation
import OSLog

private let logger = Log.wallet.store

/// Sendable — immutable config, no mutable state; safe to call off the MainActor.
final class TokenCatalogDiskCache: Sendable {
    private let namespace: String
    private let fileManager: FileManager

    init(namespace: String, fileManager: FileManager = .default) {
        self.namespace = namespace
        self.fileManager = fileManager
    }

    /// Load the last-good snapshot for `chain`, capping every token's
    /// verification at `.verified` (untrusted persistence must not confer
    /// `.curated`). Returns nil when absent / unreadable / undecodable.
    func load(chain: Chain) -> [CatalogToken]? {
        guard let url = fileURL(for: chain) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let decoded = try JSONDecoder().decode([CatalogToken].self, from: data)
            return decoded.map {
                CatalogToken(
                    meta: $0.meta,
                    verification: $0.verification.cappedForUntrustedPersistence,
                    sourceKind: $0.sourceKind
                )
            }
        } catch {
            logger.warning("[token-catalog-disk] decode failed for \(chain.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Persist `tokens` as the last-good snapshot for `chain`. Best-effort:
    /// failures are logged and swallowed (the in-memory result is already served).
    func save(_ tokens: [CatalogToken], chain: Chain) {
        guard let directory = directoryURL(), let url = fileURL(for: chain) else { return }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(tokens)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.warning("[token-catalog-disk] save failed for \(chain.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Paths

    private func directoryURL() -> URL? {
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return caches.appendingPathComponent("TokenCatalog", isDirectory: true)
            .appendingPathComponent(namespace, isDirectory: true)
    }

    private func fileURL(for chain: Chain) -> URL? {
        directoryURL()?.appendingPathComponent("\(chain.rawValue).json", isDirectory: false)
    }
}
