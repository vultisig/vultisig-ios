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
    @MainActor
    func upsert(_ positions: [BondPosition]) throws {
        let positionIDs = positions.map { $0.id }
        let fetchDescriptor = FetchDescriptor<BondPosition>(
            predicate: #Predicate<BondPosition> { position in
                positionIDs.contains(position.id)
            }
        )
        
        let existingPositions = try Storage.shared.modelContext.fetch(fetchDescriptor)
        let existingPositionsByID = Dictionary(uniqueKeysWithValues: existingPositions.map { ($0.id, $0) })
        
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
            } else {
                // Insert new position
                Storage.shared.modelContext.insert(position)
            }
        }
        
        try Storage.shared.save()
    }
}

