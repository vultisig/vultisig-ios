//
//  DefiPositionsStorageService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 10/11/2025.
//

import Foundation
import SwiftData

extension Notification.Name {
    /// Posted on the main actor after `DefiPositionsStorageService.upsert(...)` saves changes to
    /// SwiftData. SwiftUI views observing balance derived from `Vault` relationships should
    /// recompute on receipt — `@ObservedObject` does not propagate in-place mutations of nested
    /// `@Model` arrays back to the parent vault.
    static let defiPositionsDidChange = Notification.Name("com.vultisig.app.defiPositionsDidChange")
}

struct DefiPositionsStorageService {

    // MARK: - LP positions

    /// Upserts the given DTOs. No delete-stale: rows persist until the user disables the
    /// position (see `removeLP(coin2:from:)`) or the row's amount is updated by a later upsert.
    /// Lookup is keyed by `coin2` so a placeholder row inserted by `addZero(lpCoin2:...)` (with
    /// a synthesized poolName) merges with the API response that carries the canonical poolName
    /// (e.g. `ETH.USDC-0x...`).
    @discardableResult
    @MainActor
    func upsert(lp positions: [LPPositionData], for vault: Vault) throws -> [LPPosition] {
        let existingByCoin2 = Dictionary(
            vault.lpPositions.map { ($0.coin2, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        let materialized = positions.map { dto -> LPPosition in
            if let existing = existingByCoin2[dto.coin2] {
                existing.apply(dto)
                return existing
            }
            let model = LPPosition(dto, vault: vault)
            Storage.shared.modelContext.insert(model)
            return model
        }

        try saveAndNotify()
        return materialized
    }

    // MARK: - Bond positions

    /// Upserts the given bond positions and removes any persisted row not in the input.
    ///
    /// Empty input deletes everything for the vault — callers MUST distinguish a genuine "user
    /// has no bonds" from a refresh failure before passing `[]`. Bond uses a single-shot API so
    /// delete-stale is safe; stake/LP can't (per-row enable/disable).
    @MainActor
    func upsert(_ positions: [BondPosition], for vault: Vault) throws {
        let newIDs = Set(positions.map(\.id))

        for stale in vault.bondPositions where !newIDs.contains(stale.id) {
            Storage.shared.modelContext.delete(stale)
        }

        let existingByID = Dictionary(
            vault.bondPositions.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        for position in positions {
            if let existing = existingByID[position.id] {
                existing.amount = position.amount
                existing.apy = position.apy
                existing.nextReward = position.nextReward
                existing.nextChurn = position.nextChurn
            } else {
                Storage.shared.modelContext.insert(position)
            }
        }

        try saveAndNotify()
    }

    // MARK: - Stake positions

    /// Upserts the given DTOs. No delete-stale (see `upsert(lp:for:)`); rows are removed only via
    /// `removeStake(coin:from:)` when the user disables a position.
    @discardableResult
    @MainActor
    func upsert(stake positions: [StakePositionData], for vault: Vault) throws -> [StakePosition] {
        let existingByCoin = Dictionary(
            vault.stakePositions.map { ($0.coin, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        let materialized = positions.map { dto -> StakePosition in
            if let existing = existingByCoin[dto.coin] {
                existing.apply(dto)
                return existing
            }
            let model = StakePosition(dto, vault: vault)
            Storage.shared.modelContext.insert(model)
            return model
        }

        try saveAndNotify()
        return materialized
    }

    // MARK: - Enable / disable position

    /// Inserts a zero-amount stake row when the user enables a stake position, so the row is
    /// visible immediately (with its CTAs) before the first refresh completes. Idempotent.
    @MainActor
    func addZero(stakeCoin coin: CoinMeta, to vault: Vault) throws {
        guard !vault.stakePositions.contains(where: { $0.coin == coin }) else { return }
        let model = StakePosition(
            coin: coin,
            type: StakePositionType.defaultType(for: coin),
            amount: 0,
            vault: vault
        )
        Storage.shared.modelContext.insert(model)
        try saveAndNotify()
    }

    /// Removes the persisted stake row when the user disables a stake position.
    @MainActor
    func removeStake(coin: CoinMeta, from vault: Vault) throws {
        for stale in vault.stakePositions where stale.coin == coin {
            Storage.shared.modelContext.delete(stale)
        }
        try saveAndNotify()
    }

    /// Inserts a zero-amount LP row paired against the chain's native coin. Idempotent.
    @MainActor
    func addZero(lpCoin2 coin2: CoinMeta, nativeCoin: CoinMeta, to vault: Vault) throws {
        guard !vault.lpPositions.contains(where: { $0.coin2 == coin2 }) else { return }
        let model = LPPosition(
            coin1: nativeCoin,
            coin1Amount: 0,
            coin2: coin2,
            coin2Amount: 0,
            poolName: "\(coin2.chain.swapAsset).\(coin2.ticker)",
            poolUnits: "0",
            apr: 0,
            vault: vault
        )
        Storage.shared.modelContext.insert(model)
        try saveAndNotify()
    }

    /// Removes the persisted LP row when the user disables an LP position.
    @MainActor
    func removeLP(coin2: CoinMeta, from vault: Vault) throws {
        for stale in vault.lpPositions where stale.coin2 == coin2 {
            Storage.shared.modelContext.delete(stale)
        }
        try saveAndNotify()
    }
}

private extension DefiPositionsStorageService {
    @MainActor
    func saveAndNotify() throws {
        try Storage.shared.save()
        NotificationCenter.default.post(name: .defiPositionsDidChange, object: nil)
    }
}
