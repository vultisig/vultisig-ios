//
//  THORChainBondsAPI.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation

enum THORChainBondsAPI: TargetType {
    case getBondedNodes(address: String)
    case getNodeDetails(nodeAddress: String)
    case getChurns
    case getChurnInterval

    var baseURL: URL {
        switch self {
        case .getNodeDetails, .getChurnInterval:
            return URL(string: "https://thornode.ninerealms.com")!
        case .getBondedNodes, .getChurns:
            return URL(string: "https://midgard.ninerealms.com/v2")!
        }
    }

    var path: String {
        switch self {
        case .getBondedNodes(let address):
            return "/bonds/\(address)"
        case .getNodeDetails(let nodeAddress):
            return "/thorchain/node/\(nodeAddress)"
        case .getChurns:
            return "/churns"
        case .getChurnInterval:
            return "/thorchain/mimir/key/CHURNINTERVAL"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getBondedNodes, .getNodeDetails, .getChurns, .getChurnInterval:
            return .get
        }
    }

    var task: HTTPTask {
        switch self {
        case .getBondedNodes, .getNodeDetails, .getChurns, .getChurnInterval:
            return .requestPlain
        }
    }

    var headers: [String: String]? {
        switch self {
        case .getBondedNodes, .getNodeDetails, .getChurns, .getChurnInterval:
            return ["X-Client-ID": "vultisig"]
        }
    }
}
