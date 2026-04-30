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

    /// Upserts LP positions for a vault. Materializes value-type DTOs into `@Model` instances inside
    /// the model context so the interactor never has to construct `LPPosition(... vault:)` itself
    /// (which would mutate `vault.lpPositions` via the inverse relationship as a side effect).
    /// Returns the persisted `@Model` array so callers can update `@Published` state from a single
    /// stable source.
    @discardableResult
    @MainActor
    func upsert(lp positions: [LPPositionData], for vault: Vault) throws -> [LPPosition] {
        let ids = positions.map { $0.id(for: vault) }
        let fetchDescriptor = FetchDescriptor<LPPosition>(
            predicate: #Predicate<LPPosition> { position in
                ids.contains(position.id)
            }
        )
        let existing = try Storage.shared.modelContext.fetch(fetchDescriptor)
        let existingByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })

        var materialized: [LPPosition] = []
        materialized.reserveCapacity(positions.count)

        for dto in positions {
            let id = dto.id(for: vault)
            if let existing = existingByID[id] {
                existing.coin1Amount = dto.coin1Amount
                existing.coin2Amount = dto.coin2Amount
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

        try Storage.shared.save()
        NotificationCenter.default.post(name: .defiPositionsDidChange, object: nil)
        return materialized
    }

    // MARK: - Bond positions

    /// Upserts bond positions - updates existing ones or inserts new ones based on their unique ID
    /// Also removes stale positions that are no longer present in the new positions array
    @MainActor
    func upsert(_ positions: [BondPosition], for vault: Vault) throws {
        let vaultPubKey = vault.pubKeyECDSA

        // Fetch all existing bond positions for this vault
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
            try Storage.shared.save()
            NotificationCenter.default.post(name: .defiPositionsDidChange, object: nil)
            return
        }

        // Create lookup for existing positions
        let existingPositionsByID = Dictionary(allExistingPositions.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let newPositionIDs = Set(positions.map { $0.id })

        // Delete positions that are no longer present
        for existingPosition in allExistingPositions where !newPositionIDs.contains(existingPosition.id) {
            Storage.shared.modelContext.delete(existingPosition)
        }

        // Update or insert new positions
        for position in positions {
            if let existing = existingPositionsByID[position.id] {
                // Update existing position
                existing.amount = position.amount
                existing.apy = position.apy
                existing.nextReward = position.nextReward
                existing.nextChurn = position.nextChurn
            } else {
                // Insert new position
                Storage.shared.modelContext.insert(position)
            }
        }

        try Storage.shared.save()
        NotificationCenter.default.post(name: .defiPositionsDidChange, object: nil)
    }

    // MARK: - Stake positions

    /// Upserts stake positions for a vault. See `upsert(lp:for:)` for the rationale around
    /// DTO-based materialization.
    @discardableResult
    @MainActor
    func upsert(stake positions: [StakePositionData], for vault: Vault) throws -> [StakePosition] {
        let ids = positions.map { $0.id(for: vault) }
        let fetchDescriptor = FetchDescriptor<StakePosition>(
            predicate: #Predicate<StakePosition> { position in
                ids.contains(position.id)
            }
        )
        let existing = try Storage.shared.modelContext.fetch(fetchDescriptor)
        let existingByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })

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

        try Storage.shared.save()
        NotificationCenter.default.post(name: .defiPositionsDidChange, object: nil)
        return materialized
    }
}
