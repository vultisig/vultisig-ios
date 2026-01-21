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
    case getConstants

    var baseURL: URL {
        switch self {
        case .getThornameDetails,
                .getPools,
                .getPoolAsset,
                .getLastBlock,
                .getNetworkFees,
                .getConstants:
            return URL(string: "https://thornode.ninerealms.com/thorchain")!
        case .getThornameLookup,
             .getAddressLookup,
             .getHealth,
             .getNetworkInfo:
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
        case .getConstants:
            return "/constants"
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
                .getConstants,
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
                .getConstants,
                .getThornameLookup,
                .getAddressLookup,
                .getHealth,
                .getNetworkInfo:
            return .requestPlain
        }
    }

    var headers: [String: String]? {
        switch self {
        case .getThornameLookup,
             .getAddressLookup,
             .getHealth,
             .getNetworkInfo:
            return ["X-Client-ID": "vultisig"]
        case .getConstants:
            return ["X-Client-ID": "vultisig", "Content-Type": "application/json"]
        default:
            return nil
        }
    }
}

// MARK: - Response Models

/// Response model for THORChain constants
struct ThorchainConstantsResponse: Codable {
    let int_64_values: Int64Values

    struct Int64Values: Codable {
        let MinRuneForTCYStakeDistribution: UInt64
        let MinTCYForTCYStakeDistribution: UInt64?
        let TCYStakeSystemIncomeBps: UInt64?
    }
}
