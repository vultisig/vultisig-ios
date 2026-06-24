//
//  TTLCache.swift
//  VultisigApp
//
//  Generic per-key TTL cache for the swap "fetch-a-remote-list" caches
//  (`SwapKitProviderCache`). Captures the shape those caches duplicated: one
//  snapshot per key with its `fetchedAt`, a TTL,
//  in-flight `Task` coalescing so concurrent callers share one fetch, fail-open
//  to the last-good snapshot when a fetch throws, an injectable `now`, and
//  `setCached` / `clearCache` test seams.
//
//  `SwapTokenListCache` is the `@MainActor` variant of this same pattern — it
//  stays separate because it exposes a SYNCHRONOUS peek (`cached(for:)` /
//  `isStale(_:)`) that an actor can't offer without breaking its callers.
//

import Foundation

/// A per-key cache that serves a stored snapshot while it's within `ttl`,
/// otherwise refreshes it through a caller-supplied async `fetch`. Concurrent
/// refreshes for the same key share one in-flight `Task`. On a `fetch` error
/// the last-good snapshot is served when one exists; otherwise the error is
/// rethrown. `CancellationError` always propagates (the caller is tearing
/// down, so serving stale would mask the cancel).
actor TTLCache<Key: Hashable, Value> {

    private struct Entry {
        let value: Value
        let fetchedAt: Date
    }

    private var entries: [Key: Entry] = [:]
    private var inFlight: [Key: Task<Value, Error>] = [:]

    /// Returns the entry for `key` when it's within `ttl`; otherwise runs
    /// `fetch`, stores the result with `now`, and returns it. On a `fetch`
    /// error, serves the last-good entry when present, else rethrows.
    func value(
        for key: Key,
        now: Date,
        ttl: TimeInterval,
        fetch: @escaping () async throws -> Value
    ) async throws -> Value {
        if let entry = entries[key], now.timeIntervalSince(entry.fetchedAt) < ttl {
            return entry.value
        }

        let task: Task<Value, Error>
        if let existing = inFlight[key] {
            task = existing
        } else {
            let fetchTask = Task { try await fetch() }
            inFlight[key] = fetchTask
            task = fetchTask
        }
        defer {
            if inFlight[key] == task { inFlight[key] = nil }
        }

        do {
            let fresh = try await task.value
            entries[key] = Entry(value: fresh, fetchedAt: now)
            return fresh
        } catch {
            if error is CancellationError {
                throw error
            }
            if let entry = entries[key] {
                return entry.value
            }
            throw error
        }
    }

    /// Last-good value for `key`, regardless of TTL. `nil` when none is stored.
    func peek(_ key: Key) -> Value? {
        entries[key]?.value
    }

    /// Seed or replace the entry for `key` — test seam so callers don't have to
    /// stand up a fake network.
    func setCached(_ value: Value, for key: Key, fetchedAt: Date = Date()) {
        entries[key] = Entry(value: value, fetchedAt: fetchedAt)
    }

    /// Drop all entries and cancel any in-flight fetches. The next `value(for:)`
    /// refetches regardless of TTL.
    func clearCache() {
        entries.removeAll()
        for task in inFlight.values {
            task.cancel()
        }
        inFlight.removeAll()
    }
}
