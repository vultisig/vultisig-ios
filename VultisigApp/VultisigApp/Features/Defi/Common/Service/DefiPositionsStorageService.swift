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
        let vaultPubKey = vault.pubKeyECDSA
        let descriptor = FetchDescriptor<LPPosition>(
            predicate: #Predicate<LPPosition> { position in
                position.id.contains(vaultPubKey)
            }
        )
        let existingByCoin2 = Dictionary(
            try Storage.shared.modelContext.fetch(descriptor).map { ($0.coin2, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        var materialized: [LPPosition] = []
        materialized.reserveCapacity(positions.count)
        for dto in positions {
            if let existing = existingByCoin2[dto.coin2] {
                existing.coin1 = dto.coin1
                existing.coin1Amount = dto.coin1Amount
                existing.coin2Amount = dto.coin2Amount
                existing.poolName = dto.poolName
                existing.poolUnits = dto.poolUnits
                existing.apr = dto.apr
                existing.lastUpdated = .now
                materialized.append(existing)
            } else {
                let model = LPPosition(
                    coin1: dto.coin1,
                    coin1Amount: dto.coin1Amount,
                    coin2: dto.coin2,
                    coin2Amount: dto.coin2Amount,
                    poolName: dto.poolName,
                    poolUnits: dto.poolUnits,
                    apr: dto.apr,
                    vault: vault
                )
                Storage.shared.modelContext.insert(model)
                materialized.append(model)
            }
        }

        try saveAndNotify()
        return materialized
    }

    // MARK: - Bond positions

    /// Upserts bond positions - updates existing ones or inserts new ones based on their unique ID
    /// Also removes stale positions that are no longer present in the new positions array
    @MainActor
    func upsert(_ positions: [BondPosition], for vault: Vault) throws {
        let vaultPubKey = vault.pubKeyECDSA

        let allVaultPositionsDescriptor = FetchDescriptor<BondPosition>(
            predicate: #Predicate<BondPosition> { position in
                position.id.contains(vaultPubKey)
            }
        )
        let allExistingPositions = try Storage.shared.modelContext.fetch(allVaultPositionsDescriptor)

        // Callers MUST distinguish failure from a genuine empty result before passing []:
        // an empty array here will delete all persisted positions for the vault.
        if positions.isEmpty {
            for existingPosition in allExistingPositions {
                Storage.shared.modelContext.delete(existingPosition)
            }
            try saveAndNotify()
            return
        }

        let existingPositionsByID = Dictionary(allExistingPositions.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let newPositionIDs = Set(positions.map { $0.id })

        for existingPosition in allExistingPositions where !newPositionIDs.contains(existingPosition.id) {
            Storage.shared.modelContext.delete(existingPosition)
        }

        for position in positions {
            if let existing = existingPositionsByID[position.id] {
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
        let ids = positions.map { $0.id(for: vault) }
        let descriptor = FetchDescriptor<StakePosition>(
            predicate: #Predicate<StakePosition> { position in
                ids.contains(position.id)
            }
        )
        let existingByID = Dictionary(
            try Storage.shared.modelContext.fetch(descriptor).map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        var materialized: [StakePosition] = []
        materialized.reserveCapacity(positions.count)
        for dto in positions {
            let id = dto.id(for: vault)
            if let existing = existingByID[id] {
                existing.coin = dto.coin
                existing.type = dto.type
                existing.amount = dto.amount
                existing.availableToUnstake = dto.availableToUnstake
                existing.apr = dto.apr
                existing.estimatedReward = dto.estimatedReward
                existing.nextPayout = dto.nextPayout
                existing.rewards = dto.rewards
                existing.rewardCoin = dto.rewardCoin
                existing.unstakeMetadata = dto.unstakeMetadata
                materialized.append(existing)
            } else {
                let model = StakePosition(
                    coin: dto.coin,
                    type: dto.type,
                    amount: dto.amount,
                    availableToUnstake: dto.availableToUnstake,
                    apr: dto.apr,
                    estimatedReward: dto.estimatedReward,
                    nextPayout: dto.nextPayout,
                    rewards: dto.rewards,
                    rewardCoin: dto.rewardCoin,
                    unstakeMetadata: dto.unstakeMetadata,
                    vault: vault
                )
                Storage.shared.modelContext.insert(model)
                materialized.append(model)
            }
        }

        try saveAndNotify()
        return materialized
    }

    // MARK: - Enable / disable position

    /// Inserts a zero-amount stake row when the user enables a stake position, so the row is
    /// visible immediately (with its CTAs) before the first refresh completes. Idempotent: a
    /// no-op if a row for the coin already exists.
    @MainActor
    func addZero(stakeCoin coin: CoinMeta, to vault: Vault) throws {
        let id = "\(coin.chain.ticker)_\(coin.contractAddress)_\(vault.pubKeyECDSA)"
        let descriptor = FetchDescriptor<StakePosition>(
            predicate: #Predicate<StakePosition> { position in
                position.id == id
            }
        )
        guard try Storage.shared.modelContext.fetch(descriptor).isEmpty else { return }

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
        let id = "\(coin.chain.ticker)_\(coin.contractAddress)_\(vault.pubKeyECDSA)"
        let descriptor = FetchDescriptor<StakePosition>(
            predicate: #Predicate<StakePosition> { position in
                position.id == id
            }
        )
        for stale in try Storage.shared.modelContext.fetch(descriptor) {
            Storage.shared.modelContext.delete(stale)
        }
        try saveAndNotify()
    }

    /// Inserts a zero-amount LP row paired against the chain's native coin. Idempotent.
    @MainActor
    func addZero(lpCoin2 coin2: CoinMeta, nativeCoin: CoinMeta, to vault: Vault) throws {
        let vaultPubKey = vault.pubKeyECDSA
        let descriptor = FetchDescriptor<LPPosition>(
            predicate: #Predicate<LPPosition> { position in
                position.id.contains(vaultPubKey)
            }
        )
        let existing = try Storage.shared.modelContext.fetch(descriptor)
        guard !existing.contains(where: { $0.coin2 == coin2 }) else { return }

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
        let vaultPubKey = vault.pubKeyECDSA
        let descriptor = FetchDescriptor<LPPosition>(
            predicate: #Predicate<LPPosition> { position in
                position.id.contains(vaultPubKey)
            }
        )
        for stale in try Storage.shared.modelContext.fetch(descriptor) where stale.coin2 == coin2 {
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
