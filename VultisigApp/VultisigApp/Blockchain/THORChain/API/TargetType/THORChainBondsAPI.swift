//
//  THORChainBondsAPI.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation

enum THORChainBondsAPI: TargetType {
    case getBondedNodes(address: String)
    case getNodeDetails(nodeAddress: String, height: Int?)
    case getChurns
    case getChurnInterval
    case getUnbondActions(nodeAddress: String, fromHeight: Int, belowHeight: Int?)

    var baseURL: URL {
        switch self {
        case .getNodeDetails, .getChurnInterval:
            return URL(string: "https://gateway.liquify.com/chain/thorchain_api")!
        case .getBondedNodes, .getChurns, .getUnbondActions:
            return URL(string: "https://gateway.liquify.com/chain/thorchain_midgard/v2")!
        }
    }

    var path: String {
        switch self {
        case .getBondedNodes(let address):
            return "/bonds/\(address)"
        case .getNodeDetails(let nodeAddress, _):
            return "/thorchain/node/\(nodeAddress)"
        case .getChurns:
            return "/churns"
        case .getChurnInterval:
            return "/thorchain/mimir/key/CHURNINTERVAL"
        case .getUnbondActions:
            return "/actions"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getBondedNodes, .getNodeDetails, .getChurns, .getChurnInterval, .getUnbondActions:
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
        case .getBondedNodes, .getNodeDetails, .getChurns, .getChurnInterval:
            return .requestPlain
        }
    }

    var headers: [String: String]? {
        switch self {
        case .getBondedNodes, .getNodeDetails, .getChurns, .getChurnInterval, .getUnbondActions:
            return ["X-Client-ID": "vultisig"]
        }
    }
}
