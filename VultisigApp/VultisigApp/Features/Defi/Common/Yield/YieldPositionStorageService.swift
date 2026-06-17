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
            existing.depositedBalance = depositedBalance
            existing.nativeGasBalance = nativeGasBalance
            existing.lastUpdated = .now
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

    /// Returns the persisted redemption snapshots for a provider as value types.
    /// For VULT this local list is *authoritative* — it's the only record of which
    /// pending unstake requests exist (no `eth_getLogs` to re-enumerate them).
    @MainActor
    func redemptions(for vault: Vault, providerID: DefiYieldProviderID) -> [YieldRedemption] {
        guard let position = position(for: vault, providerID: providerID) else { return [] }
        return position.redemptions.map { record in
            YieldRedemption(
                id: record.id,
                amount: record.amount,
                requestedAt: record.requestedAt,
                claimableAt: record.claimableAt,
                status: record.status
            )
        }
    }

    /// Updates only the position's scalar fields (balance + gas) without touching
    /// its redemption rows. Used by providers (VULT) whose redemptions are
    /// locally-captured and must survive a balance refresh, unlike Circle
    /// where `upsert` replaces the on-chain-derived redemption snapshot wholesale.
    @MainActor
    func upsertBalanceOnly(
        providerID: DefiYieldProviderID,
        depositedBalance: Decimal,
        nativeGasBalance: Decimal,
        for vault: Vault
    ) throws {
        if let existing = position(for: vault, providerID: providerID) {
            existing.depositedBalance = depositedBalance
            existing.nativeGasBalance = nativeGasBalance
            existing.lastUpdated = .now
        } else {
            let position = YieldPosition(
                providerID: providerID,
                depositedBalance: depositedBalance,
                nativeGasBalance: nativeGasBalance,
                vault: vault
            )
            Storage.shared.insert(position)
        }
        try Storage.shared.save()
    }

    /// Appends one locally-captured redemption row (a VULT pending unstake) to a
    /// provider's position, creating the position if needed. Idempotent on the
    /// redemption id: re-capturing the same `requestId` updates the existing row
    /// rather than inserting a duplicate.
    @MainActor
    func appendRedemption(
        _ redemption: YieldRedemption,
        providerID: DefiYieldProviderID,
        depositedBalance: Decimal,
        nativeGasBalance: Decimal,
        for vault: Vault
    ) throws {
        let target: YieldPosition
        if let existing = position(for: vault, providerID: providerID) {
            existing.depositedBalance = depositedBalance
            existing.nativeGasBalance = nativeGasBalance
            existing.lastUpdated = .now
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

        if let existingRow = target.redemptions.first(where: { $0.id == redemption.id }) {
            existingRow.amount = redemption.amount
            existingRow.claimableAt = redemption.claimableAt
            existingRow.requestedAt = redemption.requestedAt
            existingRow.status = redemption.status
        } else {
            let record = YieldRedemptionRecord(
                id: redemption.id,
                amount: redemption.amount,
                requestedAt: redemption.requestedAt,
                claimableAt: redemption.claimableAt,
                status: redemption.status
            )
            record.position = target
            target.redemptions.append(record)
        }
        try Storage.shared.save()
    }

    /// Replaces a provider's redemption rows with the supplied snapshot and updates
    /// balances in one save. Used by VULT's refresh after it has merged the
    /// persisted ids with their fresh on-chain state (and pruned settled ones).
    @MainActor
    func replaceRedemptions(
        _ redemptions: [YieldRedemption],
        providerID: DefiYieldProviderID,
        depositedBalance: Decimal,
        nativeGasBalance: Decimal,
        for vault: Vault
    ) throws {
        try upsert(
            providerID: providerID,
            depositedBalance: depositedBalance,
            nativeGasBalance: nativeGasBalance,
            redemptions: redemptions,
            for: vault
        )
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

    /// Replaces the position's redemption rows with the supplied snapshot.
    @MainActor
    private func syncRedemptions(_ redemptions: [YieldRedemption], on position: YieldPosition) {
        for stale in position.redemptions {
            Storage.shared.delete(stale)
        }
        position.redemptions = redemptions.map { redemption in
            YieldRedemptionRecord(
                id: redemption.id,
                amount: redemption.amount,
                requestedAt: redemption.requestedAt,
                claimableAt: redemption.claimableAt,
                status: redemption.status
            )
        }
    }
}
