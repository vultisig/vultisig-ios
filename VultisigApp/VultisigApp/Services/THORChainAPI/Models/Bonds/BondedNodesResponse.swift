//
//  BondedNodesResponse.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation

struct BondedNodesResponse: Decodable {
    struct BondNodeResponse: Decodable {
        let status: String
        let address: String
        let bond: String
    }

    let nodes: [BondNodeResponse]
    let totalBonded: String
}
