//
//  BondNode.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import Foundation

struct BondNode: Identifiable, Equatable {
    var id: String { address }
    let address: String
    let state: BondNodeState
}

enum BondNodeState {
    case active
    case churnedOut
}
