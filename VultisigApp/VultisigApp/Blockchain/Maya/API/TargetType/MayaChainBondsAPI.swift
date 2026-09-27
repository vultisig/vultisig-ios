//
//  MayaChainBondsAPI.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/11/2025.
//

import Foundation

enum MayaChainBondsAPI: TargetType {
    case getAllNodes
    case getNodeDetails(nodeAddress: String, height: Int?)
    case getHealth
    case getNetwork
    case getChurns
    case getMimir
    case getLastBlock

    var baseURL: URL {
        switch self {
        case .getAllNodes, .getNodeDetails, .getMimir, .getLastBlock:
            return URL(string: "https://mayanode.mayachain.info")!
        case .getHealth, .getNetwork, .getChurns:
            return URL(string: "https://midgard.mayachain.info/v2")!
        }
    }

    var path: String {
        switch self {
        case .getAllNodes:
            return "/mayachain/nodes"
        case .getNodeDetails(let nodeAddress, _):
            return "/mayachain/node/\(nodeAddress)"
        case .getHealth:
            return "/health"
        case .getNetwork:
            return "/network"
        case .getChurns:
            return "/churns"
        case .getMimir:
            return "/mayachain/mimir"
        case .getLastBlock:
            return "/mayachain/lastblock"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getAllNodes, .getNodeDetails, .getHealth, .getNetwork, .getChurns, .getMimir, .getLastBlock:
            return .get
        }
    }

    var task: HTTPTask {
        switch self {
        case .getNodeDetails(_, let height?):
            return .requestParameters(["height": height], .urlEncoding)
        case .getAllNodes, .getNodeDetails, .getHealth, .getNetwork, .getChurns, .getMimir, .getLastBlock:
            return .requestPlain
        }
    }

    var headers: [String: String]? {
        switch self {
        case .getAllNodes, .getNodeDetails, .getHealth, .getNetwork, .getChurns, .getMimir, .getLastBlock:
            return ["X-Client-ID": "vultisig"]
        }
    }
}
