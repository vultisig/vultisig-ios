//
//  THORChainAPI.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

import Foundation

enum THORChainAPI: TargetType {
    case getThornameDetails(name: String)
    case getPools
    case getPoolAsset(asset: String)
    case getLastBlock
    case getNetworkInfo
    
    var baseURL: URL {
        URL(string: "https://thornode.ninerealms.com/thorchain")!
    }
    
    var path: String {
        switch self {
        case .getThornameDetails(let name):
            return "/thorname/\(name)"
        case .getLastBlock:
            return "/lastblock"
        case .getPools:
            return "/pools"
        case .getPoolAsset(let asset):
            return "/pool/\(asset)"
        case .getNetworkInfo:
            return "/network"
        }
    }
    
    var method: HTTPMethod {
        switch self {
        case .getThornameDetails,
                .getLastBlock,
                .getPools,
                .getPoolAsset,
                .getNetworkInfo:
            return .get
        }
    }
    
    var task: HTTPTask {
        switch self {
        case .getThornameDetails,
                .getLastBlock,
                .getPools,
                .getPoolAsset,
                .getNetworkInfo:
            return .requestPlain
        }
    }
}
