//
//  THORChainAPI.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

import Foundation

enum THORChainAPI: TargetType {
    case getThornameDetails(name: String)
    case getThornameLookup(name: String)
    case getAddressLookup(thorname: String)
    case getPools
    case getPoolAsset(asset: String)
    case getLastBlock
    case getNetworkFees
    case getHealth
    case getNetworkInfo
    
    var baseURL: URL {
        switch self {
        case .getThornameDetails,
                .getPools,
                .getPoolAsset,
                .getLastBlock,
                .getNetworkFees:
            return URL(string: "https://thornode.ninerealms.com/thorchain")!
        case .getThornameLookup, .getAddressLookup, .getHealth, .getNetworkInfo:
            return URL(string: "https://midgard.ninerealms.com")!
        }
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
        case .getNetworkFees:
            return "/network"
        case .getThornameLookup(let name):
            return "/v2/thorname/lookup/\(name)"
        case .getAddressLookup(let thorname):
            return "/v2/thorname/rlookup/\(thorname)"
        case .getHealth:
            return "/v2/health"
        case .getNetworkInfo:
            return "/v2/network"
        }
    }
    
    var method: HTTPMethod {
        switch self {
        case .getThornameDetails,
                .getLastBlock,
                .getPools,
                .getPoolAsset,
                .getNetworkFees,
                .getThornameLookup,
                .getAddressLookup,
                .getHealth,
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
                .getNetworkFees,
                .getThornameLookup,
                .getAddressLookup,
                .getHealth,
                .getNetworkInfo:
            return .requestPlain
        }
    }
    
    var headers: [String : String]? {
        switch self {
        case .getThornameLookup, .getAddressLookup, .getHealth, .getNetworkInfo:
            return ["X-Client-ID": "vultisig"]
        default:
            return nil
        }
    }
}
