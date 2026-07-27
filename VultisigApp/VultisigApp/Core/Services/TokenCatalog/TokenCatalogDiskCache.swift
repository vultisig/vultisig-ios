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
//  TRUST: this is untrusted persistence — a file must not be able to confer
//  trust. On load every token's verification is floored to `.unverified`, so a
//  disk-loaded (offline cold-start) token never auto-surfaces on the strength of
//  a persisted verification. Auto-surfacing offline comes from the in-memory
//  `BundledTokensProvider` (curated); disk tokens stay reachable via explicit
//  search (badged) per verification-to-surface. Verification is never decoded
//  from a third-party source payload — providers assign it in code from a live
//  signal, and that live decision is intentionally NOT trusted back off disk.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "token-catalog-disk-cache")

/// Sendable — immutable config, no mutable state; safe to call off the MainActor.
final class TokenCatalogDiskCache: Sendable {
    private let namespace: String
    private let fileManager: FileManager

    init(namespace: String, fileManager: FileManager = .default) {
        self.namespace = namespace
        self.fileManager = fileManager
    }

    /// Load the last-good snapshot for `chain`, flooring every token's
    /// verification to `.unverified` (untrusted persistence must not confer
    /// trust). Returns nil when absent / unreadable / undecodable.
    func load(chain: Chain) -> [CatalogToken]? {
        guard let url = fileURL(for: chain) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let decoded = try JSONDecoder().decode([CatalogToken].self, from: data)
            return decoded.map {
                CatalogToken(meta: $0.meta, verification: .unverified, sourceKind: $0.sourceKind)
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
