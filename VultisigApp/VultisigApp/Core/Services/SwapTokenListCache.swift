//
//  SwapTokenListCache.swift
//  VultisigApp
//
//  Per-chain, vault-independent cache for the swap "Select asset" picker's
//  remote/preset token list (the `TokenSearchService.loadTokens` output:
//  1inch on EVM, Jupiter on Solana, plus the local preset tokens). Keyed by
//  `Chain` with a per-chain `fetchedAt` so loading one chain never evicts a
//  fresh entry for another. Modeled on `SwapKitTokensCache` /
//  `SwapKitProviderCache`: in-flight `Task` coalescing so concurrent picker
//  opens share one fetch, and fail-open to the last-good entry when a fetch
//  throws.
//
//  Only the vault-INDEPENDENT list is cached here. The picker re-merges the
//  vault's held coins (which change at runtime) on every open, so the merged
//  result is never cached.
//
//  This is the `@MainActor` variant of the generic `TTLCache` pattern: it stays
//  separate because it exposes a SYNCHRONOUS peek (`cached(for:)` / `isStale`)
//  that `SwapCoinSelectionViewModel` relies on, which an actor can't offer.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "swap-token-list-cache")

@MainActor
final class SwapTokenListCache {
    static let shared = SwapTokenListCache()

    private struct Entry {
        let tokens: [CoinMeta]
        let fetchedAt: Date
    }

    private let ttl: TimeInterval
    private var entries: [Chain: Entry] = [:]
    private var inFlight: [Chain: Task<[CoinMeta], Error>] = [:]

    init(ttl: TimeInterval = SwapKitConfig.swapTokenListCacheTTL) {
        self.ttl = ttl
    }

    /// Synchronous peek — returns the cached tokens for `chain` if an entry
    /// exists, regardless of TTL. Used by the MainActor view model to serve
    /// the picker instantly (no spinner) on re-select.
    func cached(for chain: Chain) -> [CoinMeta]? {
        entries[chain]?.tokens
    }

    /// Whether the cached entry for `chain` is older than the TTL (or absent).
    /// A missing entry is treated as stale so callers refresh it.
    func isStale(_ chain: Chain, now: Date = Date()) -> Bool {
        guard let entry = entries[chain] else { return true }
        return now.timeIntervalSince(entry.fetchedAt) >= ttl
    }

    /// Returns a fresh entry when within TTL; otherwise runs `fetch`, stores
    /// the result with `now`, and returns it. Concurrent calls for the same
    /// chain share one in-flight `Task`. On `fetch` error, falls open to the
    /// last-good entry (returns stale) rather than throwing, when one exists.
    func tokens(
        for chain: Chain,
        now: Date = Date(),
        fetch: @escaping () async throws -> [CoinMeta]
    ) async throws -> [CoinMeta] {
        if let entry = entries[chain], now.timeIntervalSince(entry.fetchedAt) < ttl {
            return entry.tokens
        }

        let task: Task<[CoinMeta], Error>
        if let inFlight = inFlight[chain] {
            task = inFlight
        } else {
            let fetchTask = Task { try await fetch() }
            inFlight[chain] = fetchTask
            task = fetchTask
        }
        defer {
            if inFlight[chain] == task { inFlight[chain] = nil }
        }

        do {
            let fresh = try await task.value
            entries[chain] = Entry(tokens: fresh, fetchedAt: now)
            return fresh
        } catch {
            // Cooperative cancellation must propagate — the caller is tearing
            // down, so fail-open (serving stale) would mask the cancel. Only real
            // fetch failures fall back to the last-good entry.
            if error is CancellationError {
                throw error
            }
            if let entry = entries[chain] {
                logger.warning("[swap-token-list] fetch failed for \(chain.rawValue, privacy: .public), serving last-good: \(String(describing: error), privacy: .public)")
                return entry.tokens
            }
            throw error
        }
    }

    /// Seed the cache — exposed for tests + debug so they don't need a fake
    /// network. Mirrors `SwapKitProviderCache.setSnapshot`.
    func setCached(_ tokens: [CoinMeta], for chain: Chain, fetchedAt: Date = Date()) {
        entries[chain] = Entry(tokens: tokens, fetchedAt: fetchedAt)
    }

    /// Drop all cached entries + in-flight tasks. Next `tokens(for:)` refetches
    /// regardless of TTL.
    func clearCache() {
        entries.removeAll()
        for task in inFlight.values {
            task.cancel()
        }
        inFlight.removeAll()
    }
}
