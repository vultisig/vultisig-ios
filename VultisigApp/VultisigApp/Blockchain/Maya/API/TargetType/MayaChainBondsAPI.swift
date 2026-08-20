//
//  MayaChainBondsAPI.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/11/2025.
//

import Foundation

enum MayaChainBondsAPI: TargetType {
    case getAllNodes
    case getNodeDetails(nodeAddress: String)
    case getHealth
    case getNetwork
    case getMimir
    case getLastBlock

    var baseURL: URL {
        switch self {
        case .getAllNodes, .getNodeDetails, .getMimir, .getLastBlock:
            return URL(string: "https://mayanode.mayachain.info")!
        case .getHealth:
            return URL(string: "https://midgard.mayachain.info/v2")!
        case .getNetwork:
            return URL(string: "https://midgard.mayachain.info/v2")!
        }
    }

    var path: String {
        switch self {
        case .getAllNodes:
            return "/mayachain/nodes"
        case .getNodeDetails(let nodeAddress):
            return "/mayachain/node/\(nodeAddress)"
        case .getHealth:
            return "/health"
        case .getNetwork:
            return "/network"
        case .getMimir:
            return "/mayachain/mimir"
        case .getLastBlock:
            return "/mayachain/lastblock"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getAllNodes, .getNodeDetails, .getHealth, .getNetwork, .getMimir, .getLastBlock:
            return .get
        }
    }

    var task: HTTPTask {
        switch self {
        case .getAllNodes, .getNodeDetails, .getHealth, .getNetwork, .getMimir, .getLastBlock:
            return .requestPlain
        }
    }

    var headers: [String: String]? {
        switch self {
        case .getAllNodes, .getNodeDetails, .getHealth, .getNetwork, .getMimir, .getLastBlock:
            return ["X-Client-ID": "vultisig"]
        }
    }
}
