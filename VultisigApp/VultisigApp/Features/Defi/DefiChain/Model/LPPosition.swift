//
//  LPPosition.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/10/2025.
//

import Foundation
import SwiftData

@Model
final class LPPosition {
    @Attribute(.unique) var id: String

    var coin1: CoinMeta
    var coin1Amount: Decimal
    var coin2: CoinMeta
    var coin2Amount: Decimal
    var poolName: String?
    var poolUnits: String?
    var apr: Double
    var lastUpdated: Date = Date.now

    @Relationship(inverse: \Vault.lpPositions) var vault: Vault?

    init(
        coin1: CoinMeta,
        coin1Amount: Decimal,
        coin2: CoinMeta,
        coin2Amount: Decimal,
        poolName: String,
        poolUnits: String,
        apr: Double,
        vault: Vault
    ) {
        self.coin1 = coin1
        self.coin1Amount = coin1Amount
        self.coin2 = coin2
        self.coin2Amount = coin2Amount
        self.apr = apr
        self.poolName = poolName
        self.poolUnits = poolUnits
        self.lastUpdated = Date.now
        self.vault = vault
        self.id = "\(coin1.chain.ticker)_\(coin1.contractAddress)_\(poolName)_\(vault.pubKeyECDSA)"
    }
}
