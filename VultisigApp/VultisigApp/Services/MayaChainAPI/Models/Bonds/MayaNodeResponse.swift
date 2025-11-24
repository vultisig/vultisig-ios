//
//  MayaNodeResponse.swift
//  VultisigApp
//
//  Created by AI Assistant on 23/11/2025.
//

import Foundation

/// Response model for Maya node from /mayachain/nodes
struct MayaNodeResponse: Decodable {
    let nodeAddress: String
    let status: String
    let bond: String
    let bondProviders: BondProvidersInfo
    let currentAward: String

    enum CodingKeys: String, CodingKey {
        case nodeAddress = "node_address"
        case status
        case bond
        case bondProviders = "bond_providers"
        case currentAward = "current_award"
    }

    struct BondProvidersInfo: Decodable {
        let nodeOperatorFee: String
        let providers: [BondProvider]

        enum CodingKeys: String, CodingKey {
            case nodeOperatorFee = "node_operator_fee"
            case providers
        }
    }

    struct BondProvider: Decodable {
        let bondAddress: String
        let bond: String
        let pools: [String: String]  // asset -> LP units

        enum CodingKeys: String, CodingKey {
            case bondAddress = "bond_address"
            case bond
            case pools
        }
    }
}

/// Processed bond node data
struct MayaBondedNodes {
    let totalBonded: Decimal
    let nodes: [MayaBondNode]
}

struct MayaBondNode: Identifiable, Hashable, Codable {
    var id: String { address }
    let status: String
    let address: String
    let bond: Decimal

    var shortAddress: String {
        guard address.count > 4 else { return address }
        return String(address.suffix(4))
    }
}
