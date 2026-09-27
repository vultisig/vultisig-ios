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

    /// The previous churn's realized reward (`myAward` at `height - 1`),
    /// shown on the card as "Last Reward". Deliberately session-scoped, not
    /// part of the persisted schema: SwiftData does not observation-track
    /// `@Transient` properties, so this hangs off an `ObservedTransient` box
    /// the same way `Vault.fastVaultCheckedTopology` does. `nil` means either
    /// "not fetched yet this session" or "this vault had no prior churn
    /// while bonded" — both render the same "no fake Last Reward" state.
    @Transient private var lastRewardBox = ObservedTransient<Decimal?>(nil)

    var lastReward: Decimal? {
        get { lastRewardBox.value }
        set { lastRewardBox.value = newValue }
    }

    init(
        node: BondNode,
        amount: Decimal,
        apy: Double,
        nextReward: Decimal,
        nextChurn: Date? = nil,
        lastReward: Decimal? = nil,
        vault: Vault
    ) {
        self.node = node
        self.amount = amount
        self.apy = apy
        self.nextReward = nextReward
        self.nextChurn = nextChurn
        self.vault = vault
        self.id = "\(node.coin.chain.ticker)_\(node.coin.contractAddress)_\(node.address)_\(vault.pubKeyECDSA)"
        self.lastReward = lastReward
    }
}
