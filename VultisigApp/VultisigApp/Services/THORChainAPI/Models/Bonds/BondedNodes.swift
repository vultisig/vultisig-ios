//
//  BondedNodes.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation

struct BondedNodes {
    let totalBonded: Decimal
    let nodes: [RuneBondNode]
}

struct RuneBondNode: Identifiable, Codable {
    var id: String { address }
    let status: String
    let address: String
    let bond: Decimal

    var shortAddress: String {
        guard address.count > 4 else { return address }
        return String(address.suffix(4))
    }
}
