//
//  YieldPositionStorageService.swift
//  VultisigApp
//

import Foundation
import SwiftData

/// `@MainActor` upsert/read of the generalized `YieldPosition` cache and the
/// one-time migration of legacy `CirclePosition` rows into it.
struct YieldPositionStorageService {

    @MainActor
    func position(for vault: Vault, providerID: DefiYieldProviderID) -> YieldPosition? {
        vault.yieldPositions.first { $0.providerRawID == providerID.rawValue }
    }

    @MainActor
    func upsert(
        providerID: DefiYieldProviderID,
        depositedBalance: Decimal,
        nativeGasBalance: Decimal,
        redemptions: [YieldRedemption],
        for vault: Vault
    ) throws {
        let target: YieldPosition
        if let existing = position(for: vault, providerID: providerID) {
            applyBalances(depositedBalance: depositedBalance, nativeGasBalance: nativeGasBalance, to: existing)
            target = existing
        } else {
            let position = YieldPosition(
                providerID: providerID,
                depositedBalance: depositedBalance,
                nativeGasBalance: nativeGasBalance,
                vault: vault
            )
            Storage.shared.insert(position)
            target = position
        }
        syncRedemptions(redemptions, on: target)
        try Storage.shared.save()
    }

    /// One-time, idempotent backfill: copies a pre-existing `CirclePosition`
    /// into a `YieldPosition(.circle)` so users who already deposited via Circle
    /// keep their cached position after the refactor. Safe to call repeatedly —
    /// it returns immediately once the migrated row exists.
    @MainActor
    func migrateCirclePositionIfNeeded(for vault: Vault) throws {
        guard let legacy = vault.circlePosition else { return }
        guard position(for: vault, providerID: .circle) == nil else { return }

        let position = YieldPosition(
            providerID: .circle,
            depositedBalance: legacy.usdcBalance,
            nativeGasBalance: legacy.ethBalance,
            vault: vault
        )
        Storage.shared.insert(position)
        try Storage.shared.save()
    }

    // MARK: - Private

    /// Copies the refreshed balances onto `position`, or leaves it entirely alone
    /// when neither moved.
    ///
    /// The equality guard is load-bearing, not an optimization. SwiftData's
    /// `@Model` setter wraps each store in `withMutation(of:)`, which notifies
    /// observers **without comparing** the new value to the old — so re-assigning a
    /// value that is already there still invalidates every SwiftUI view reading
    /// this position. A plain `@Observable` class does not behave this way, which is
    /// why the habit of assigning blind is safe elsewhere and not here. A refresh
    /// re-supplies the same balances whenever nothing moved on-chain, so an
    /// unguarded copy re-dirties its readers on every single call.
    ///
    /// Two properties of the guard matter: it must cover **every** write below,
    /// the `lastUpdated` stamp included — a stamp left outside re-notifies by
    /// itself and defeats the guard entirely — and it must compare **every** field
    /// that is assigned, or an uncompared field re-opens the same hole. Add to both
    /// lists together.
    ///
    /// `lastUpdated` has no readers: nothing checks this position for staleness,
    /// expires it, sorts on it, or filters on it, so declining to re-stamp a no-op
    /// refresh is not observable behaviour.
    @MainActor
    private func applyBalances(
        depositedBalance: Decimal,
        nativeGasBalance: Decimal,
        to position: YieldPosition
    ) {
        guard position.depositedBalance != depositedBalance
            || position.nativeGasBalance != nativeGasBalance
        else { return }

        position.depositedBalance = depositedBalance
        position.nativeGasBalance = nativeGasBalance
        position.lastUpdated = .now
    }

    /// Reconciles the position's redemption rows against `redemptions`, matching
    /// stored rows to incoming ones by `id`.
    ///
    /// This is a diff rather than the obvious delete-everything-and-recreate,
    /// because an equality guard cannot rescue the latter: deleting and
    /// re-inserting rows that did not change is itself a store mutation, so it
    /// invalidates every reader — and, once the caller saves, every `@Query` in
    /// the app — on every refresh, however little actually moved. Only touching
    /// what genuinely differs is what stops that.
    ///
    /// `id` is the identity: it is the provider's own redemption-request
    /// identifier, it is what `YieldRedemptionRecord` already persists
    /// `@Attribute(.unique)`, and it is the key the read path maps back out on.
    /// It is deliberately not derived from the mutable fields — a redemption
    /// keeps its identity precisely while it moves `pending -> claimable ->
    /// settled`, which is the update this diff has to recognize as an update
    /// rather than as a delete plus an insert.
    ///
    /// Row order is not a contract and is not maintained here. A SwiftData
    /// to-many relationship is unordered, so the wholesale assignment this
    /// replaced did not preserve the snapshot's order either; imposing one would
    /// need a persisted sort index, and rewriting the relationship whenever the
    /// provider reorders its list would put back exactly the churn this removes.
    /// Readers that need a specific redemption should select it, not index into
    /// the array.
    @MainActor
    private func syncRedemptions(_ redemptions: [YieldRedemption], on position: YieldPosition) {
        // `id` is `@Attribute(.unique)`, so two incoming rows sharing one would
        // collapse into a single stored row anyway; keep the first and drop the
        // rest here, where it is explicit.
        var seen = Set<String>()
        let incoming = redemptions.filter { seen.insert($0.id).inserted }
        let incomingByID = Dictionary(uniqueKeysWithValues: incoming.map { ($0.id, $0) })
        var matched: [String: YieldRedemptionRecord] = [:]

        // Keep the first stored row per incoming id; delete the rest. A row whose
        // id is absent from the snapshot is genuinely gone, and a second row
        // carrying an already-matched id is a duplicate the store should not hold.
        for stored in position.redemptions {
            if incomingByID[stored.id] != nil, matched[stored.id] == nil {
                matched[stored.id] = stored
            } else {
                Storage.shared.delete(stored)
            }
        }

        for redemption in incoming {
            guard let record = matched[redemption.id] else { continue }
            apply(redemption, to: record)
        }

        // New rows are attached through the inverse rather than by appending to
        // `position.redemptions`: appending is a get-modify-set of the whole
        // relationship, and the rows deleted just above may still be in the array
        // the getter hands back, which would write them straight back in.
        for redemption in incoming where matched[redemption.id] == nil {
            let record = YieldRedemptionRecord(
                id: redemption.id,
                amount: redemption.amount,
                requestedAt: redemption.requestedAt,
                claimableAt: redemption.claimableAt,
                status: redemption.status
            )
            Storage.shared.insert(record)
            record.position = position
        }
    }

    /// Copies a refreshed redemption onto its stored row, or leaves the row
    /// entirely alone when nothing differs — same all-or-nothing guard, and same
    /// reason, as ``applyBalances(depositedBalance:nativeGasBalance:to:)``.
    /// `id` is the match key and is never written.
    @MainActor
    private func apply(_ redemption: YieldRedemption, to record: YieldRedemptionRecord) {
        guard record.amount != redemption.amount
            || record.requestedAt != redemption.requestedAt
            || record.claimableAt != redemption.claimableAt
            || record.status != redemption.status
        else { return }

        record.amount = redemption.amount
        record.requestedAt = redemption.requestedAt
        record.claimableAt = redemption.claimableAt
        record.status = redemption.status
    }
}
