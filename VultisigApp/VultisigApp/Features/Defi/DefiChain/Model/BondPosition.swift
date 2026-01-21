//
//  BondPosition.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import Foundation
import SwiftData

@Model
final class BondPosition {
    @Attribute(.unique) var id: String

    var node: BondNode
    var amount: Decimal
    var apy: Double
    var nextReward: Decimal
    var nextChurn: Date?

    @Relationship(inverse: \Vault.bondPositions) var vault: Vault?

    init(
        node: BondNode,
        amount: Decimal,
        apy: Double,
        nextReward: Decimal,
        nextChurn: Date? = nil,
        vault: Vault
    ) {
        self.node = node
        self.amount = amount
        self.apy = apy
        self.nextReward = nextReward
        self.nextChurn = nextChurn
        self.vault = vault
        self.id = "\(node.coin.chain.ticker)_\(node.coin.contractAddress)_\(node.address)_\(vault.pubKeyECDSA)"
    }
}
