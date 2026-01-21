//
//  DefiPositionsStorageService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 10/11/2025.
//

import Foundation
import SwiftData

struct DefiPositionsStorageService {
    /// Upserts LP positions - updates existing ones or inserts new ones based on their unique ID
    @MainActor
    func upsert(_ positions: [LPPosition]) throws {
        let positionIDs = positions.map { $0.id }
        let fetchDescriptor = FetchDescriptor<LPPosition>(
            predicate: #Predicate<LPPosition> { position in
                positionIDs.contains(position.id)
            }
        )
        
        let existingPositions = try Storage.shared.modelContext.fetch(fetchDescriptor)
        let existingPositionsByID = Dictionary(uniqueKeysWithValues: existingPositions.map { ($0.id, $0) })
        
        for position in positions {
            if let existing = existingPositionsByID[position.id] {
                // Update existing position
                existing.coin1Amount = position.coin1Amount
                existing.coin2Amount = position.coin2Amount
                existing.apr = position.apr
                existing.lastUpdated = position.lastUpdated
            } else {
                // Insert new position
                Storage.shared.modelContext.insert(position)
            }
        }
        
        try Storage.shared.save()
    }
    
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

        // If no new positions, delete all existing ones for this vault
        if positions.isEmpty {
            for existingPosition in allExistingPositions {
                Storage.shared.modelContext.delete(existingPosition)
            }
            try Storage.shared.save()
            return
        }

        // Create lookup for existing positions
        let existingPositionsByID = Dictionary(uniqueKeysWithValues: allExistingPositions.map { ($0.id, $0) })
        let newPositionIDs = Set(positions.map { $0.id })

        // Delete positions that are no longer present
        for existingPosition in allExistingPositions {
            if !newPositionIDs.contains(existingPosition.id) {
                Storage.shared.modelContext.delete(existingPosition)
            }
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
    }
    
    /// Upserts stake positions - updates existing ones or inserts new ones based on their unique ID
    @MainActor
    func upsert(_ positions: [StakePosition]) throws {
        let positionIDs = positions.map { $0.id }
        let fetchDescriptor = FetchDescriptor<StakePosition>(
            predicate: #Predicate<StakePosition> { position in
                positionIDs.contains(position.id)
            }
        )
        
        let existingPositions = try Storage.shared.modelContext.fetch(fetchDescriptor)
        let existingPositionsByID = Dictionary(uniqueKeysWithValues: existingPositions.map { ($0.id, $0) })
        
        for position in positions {
            if let existing = existingPositionsByID[position.id] {
                // Update existing position
                existing.amount = position.amount
                existing.apr = position.apr
                existing.estimatedReward = position.estimatedReward
                existing.nextPayout = position.nextPayout
                existing.rewards = position.rewards
                existing.rewardCoin = position.rewardCoin
                existing.unstakeMetadata = position.unstakeMetadata
            } else {
                // Insert new position
                Storage.shared.modelContext.insert(position)
            }
        }
        
        try Storage.shared.save()
    }
}
