//
//  SecuredAssetTokenProvider.swift
//  VultisigApp
//
//  Destination-token source for the swap coin picker that surfaces the
//  THORChain secured-asset universe (from `SecuredAssetCatalog`) so a user
//  can discover and swap *into* any secured asset — not only the ones the
//  vault already holds. Every secured asset lives on `.thorChain` (its denom
//  is stored as the token's `contractAddress`), so this provider emits a
//  single bucket keyed to `.thorChain` and an empty bucket for every other
//  chain. The picker aggregates it alongside the curated + SwapKit + native
//  pool lists via `DestinationTokenRegistry`, deduping by `CoinMeta.uniqueId`
//  (so a held secured coin collapses onto its catalog twin but still shows
//  its balance).
//
//  Registered once at app startup (see `VultisigApp.init`).
//

import Foundation

@MainActor
final class SecuredAssetTokenProvider {

    let providerKind: String = "thorchainSecured"

    private let catalog: SecuredAssetCatalog
    private let cacheTTL: TimeInterval = 5 * 60
    private var snapshot: Snapshot?
    private var inFlight: Task<DestinationTokenBucket, Never>?

    private struct Snapshot {
        let bucket: DestinationTokenBucket
        let fetchedAt: Date
    }

    // The catalog default is resolved inside the body (not as a default-argument
    // expression) so the @MainActor-isolated `SecuredAssetCatalog` init isn't
    // called from the caller's nonisolated context — same pattern as
    // `SwapCoinSelectionLogic.init` resolving `DestinationTokenRegistry.shared`.
    init(catalog: SecuredAssetCatalog? = nil) {
        self.catalog = catalog ?? SecuredAssetCatalog()
    }

    /// Coalescing build of the `.thorChain` secured-asset bucket — concurrent
    /// callers share one in-flight Task. Returns the cached snapshot while
    /// fresh; otherwise re-derives from the catalog.
    ///
    /// The catalog never throws (it falls back to a small static list when the
    /// live `/securedassets` fetch fails), so the bucket is always populated.
    /// The underlying network fetch is itself governed by
    /// `ThorchainService.fetchSecuredAssets`'s 5-minute cache, so `forceRefresh`
    /// bypasses this provider's TTL to re-derive the bucket while staying cheap
    /// and offline-safe.
    private func ensureSnapshot(forceRefresh: Bool) async -> DestinationTokenBucket {
        let now = Date()
        if !forceRefresh, let snapshot, now.timeIntervalSince(snapshot.fetchedAt) < cacheTTL {
            return snapshot.bucket
        }
        if let inFlight {
            return await inFlight.value
        }
        let task = Task { [catalog] () -> DestinationTokenBucket in
            let metas = await catalog.coinMetas()
            return DestinationTokenBucket(
                chain: .thorChain,
                tokens: metas,
                uniqueIds: Set(metas.map { $0.uniqueId })
            )
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        snapshot = Snapshot(bucket: result, fetchedAt: now)
        return result
    }
}

// Conformance lives in an explicit extension (rather than on the primary
// declaration) so the protocol-witness match for the async `tokens(for:)`
// requirement is resolved independently of the @MainActor class body — the
// same defensiveness `NativePoolTokenProvider` applies.
extension SecuredAssetTokenProvider: DestinationTokenProvider {
    func tokens(for chain: Chain, forceRefresh: Bool) async -> DestinationTokenBucket {
        guard chain == .thorChain else { return .empty(chain: chain) }
        return await ensureSnapshot(forceRefresh: forceRefresh)
    }
}
