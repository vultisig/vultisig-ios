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
    case getUnbondActions(nodeAddress: String, fromHeight: Int, belowHeight: Int?)

    var baseURL: URL {
        switch self {
        case .getAllNodes, .getNodeDetails, .getMimir, .getLastBlock:
            return URL(string: "https://mayanode.mayachain.info")!
        case .getHealth, .getNetwork, .getChurns, .getUnbondActions:
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
        case .getUnbondActions:
            return "/actions"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getAllNodes, .getNodeDetails, .getHealth, .getNetwork, .getChurns, .getMimir, .getLastBlock, .getUnbondActions:
            return .get
        }
    }

    var task: HTTPTask {
        switch self {
        case .getNodeDetails(_, let height?):
            return .requestParameters(["height": height], .urlEncoding)
        case .getUnbondActions(let nodeAddress, let fromHeight, let belowHeight):
            var params: [String: Any] = [
                "address": nodeAddress,
                "type": "unbond",
                "fromHeight": fromHeight,
                "limit": BondRewardHistoryConfig.unbondPageSize
            ]
            // Midgard's `height` is an exclusive upper bound.
            params["height"] = belowHeight
            return .requestParameters(params, .urlEncoding)
        case .getAllNodes, .getNodeDetails, .getHealth, .getNetwork, .getChurns, .getMimir, .getLastBlock:
            return .requestPlain
        }
    }

    var headers: [String: String]? {
        switch self {
        case .getAllNodes, .getNodeDetails, .getHealth, .getNetwork, .getChurns, .getMimir, .getLastBlock, .getUnbondActions:
            return ["X-Client-ID": "vultisig"]
        }
    }
}
