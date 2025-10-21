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
    case getNetworkInfo
    
    var baseURL: URL {
        switch self {
        case .getThornameDetails,
                .getPools,
                .getPoolAsset,
                .getLastBlock,
                .getNetworkInfo:
            return URL(string: "https://thornode.ninerealms.com/thorchain")!
        case .getThornameLookup, .getAddressLookup:
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
        case .getNetworkInfo:
            return "/network"
        case .getThornameLookup(let name):
            return "/v2/thorname/lookup/\(name)"
        case .getAddressLookup(let thorname):
            return "/v2/thorname/rlookup/\(thorname)"
        }
    }
    
    var method: HTTPMethod {
        switch self {
        case .getThornameDetails,
                .getLastBlock,
                .getPools,
                .getPoolAsset,
                .getNetworkInfo,
                .getThornameLookup,
                .getAddressLookup:
            return .get
        }
    }
    
    var task: HTTPTask {
        switch self {
        case .getThornameDetails,
                .getLastBlock,
                .getPools,
                .getPoolAsset,
                .getNetworkInfo,
                .getThornameLookup,
                .getAddressLookup:
            return .requestPlain
        }
    }
    
    var headers: [String : String]? {
        switch self {
        case .getThornameLookup, .getAddressLookup:
            return ["X-Client-ID": "vultisig"]
        default:
            return nil
        }
    }
}
