//
//  ActiveBondedNode.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import Foundation

struct ActiveBondedNode: Identifiable, Equatable {
    var id: String { node.address }
    
    let node: BondNode
    let amount: Decimal
    let apy: Double
    let nextReward: Decimal
    let nextChurn: TimeInterval
}
