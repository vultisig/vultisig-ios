//
//  THORChainBondsAPI.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation

enum THORChainBondsAPI: TargetType {
    case getNodes
    case getBondedNodes(address: String)
    
    
    var baseURL: URL {
        return URL(string: "https://midgard.ninerealms.com/v2")!
    }
    
    var path: String {
        switch self {
        case .getNodes:
            return "/nodes"
        case .getBondedNodes(let address):
            return "/bonds/\(address)"
        }
    }
    
    var method: HTTPMethod {
        switch self {
        case .getNodes, .getBondedNodes:
            return .get
        }
    }
    
    var task: HTTPTask {
        switch self {
        case .getNodes, .getBondedNodes:
            return .requestPlain
        }
    }
    
    var headers: [String : String]? {
        switch self {
        case .getNodes, .getBondedNodes:
            return ["X-Client-ID": "vultisig"]
        }
    }
}
