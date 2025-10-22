//
//  NodeDetailsResponse.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation

/// Response model for THORChain node details
/// Endpoint: GET https://thornode.ninerealms.com/thorchain/node/{node_address}
struct NodeDetailsResponse: Decodable {
    let nodeAddress: String
    let status: String
    let bondProviders: BondProvidersInfo
    let currentAward: String

    enum CodingKeys: String, CodingKey {
        case nodeAddress = "node_address"
        case status
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

        enum CodingKeys: String, CodingKey {
            case bondAddress = "bond_address"
            case bond
        }
    }
}
