//
//  MayaChainLPsAPI.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 25/11/2025.
//

import Foundation

enum MayaChainLPsAPI: TargetType {
    case getPoolStats(period: String?)
    case getMemberDetails(address: String)
    /// A vault's record on one pool, read from the node: Midgard has no view of
    /// a half-open add.
    case getLiquidityProvider(pool: String, address: String)

    var baseURL: URL {
        switch self {
        case .getPoolStats:
            return URL(string: "https://midgard.mayachain.info")!
        case .getMemberDetails:
            return URL(string: "https://midgard.mayachain.info")!
        case .getLiquidityProvider:
            return URL(string: "https://mayanode.mayachain.info")!
        }
    }

    var path: String {
        switch self {
        case .getPoolStats:
            return "/v2/pools"
        case .getMemberDetails(let address):
            return "/v2/member/\(address)"
        case .getLiquidityProvider(let pool, let address):
            return "/mayachain/pool/\(pool)/liquidity_provider/\(address)"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getPoolStats, .getMemberDetails, .getLiquidityProvider:
            return .get
        }
    }

    var task: HTTPTask {
        switch self {
        case .getPoolStats(let period):
            var params: [String: String] = ["status": "available"]
            if let period = period {
                params["period"] = period
            } else {
                // Default to 30d for consistency
                params["period"] = "30d"
            }
            return .requestParameters(params, .urlEncoding)

        case .getMemberDetails, .getLiquidityProvider:
            return .requestPlain
        }
    }

    var headers: [String: String]? {
        return ["X-Client-ID": "vultisig"]
    }
}
