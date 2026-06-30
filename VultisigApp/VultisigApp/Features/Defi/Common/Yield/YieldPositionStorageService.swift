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
