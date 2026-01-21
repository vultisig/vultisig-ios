//
//  THORChainLPsAPI.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation

enum THORChainLPsAPI: TargetType {
    case getLiquidityProviderDetails(assetId: String, address: String)
    case getPoolStats(period: String?)
    case getDepthHistory(asset: String, interval: String, count: Int)

    var baseURL: URL {
        switch self {
        case .getLiquidityProviderDetails:
            return URL(string: "https://thornode.ninerealms.com")!
        default:
            return URL(string: "https://midgard.ninerealms.com")!
        }
    }

    var path: String {
        switch self {
        case .getLiquidityProviderDetails(let assetId, let address):
            return "/thorchain/pool/\(assetId)/liquidity_provider/\(address)"
        case .getPoolStats:
            return "/v2/pools"
        case .getDepthHistory(let asset, _, _):
            return "/v2/history/depths/\(asset)"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getLiquidityProviderDetails, .getPoolStats, .getDepthHistory:
            return .get
        }
    }

    var task: HTTPTask {
        switch self {
        case .getLiquidityProviderDetails:
            return .requestPlain

        case .getPoolStats(let period):
            var params: [String: String] = ["status": "available"]
            if let period = period {
                params["period"] = period
            } else {
                // Default to 30d for consistency with thorchain.org
                params["period"] = "30d"
            }
            return .requestParameters(params, .urlEncoding)

        case .getDepthHistory(_, let interval, let count):
            return .requestParameters([
                "interval": interval,
                "count": String(count)
            ], .urlEncoding)
        }
    }

    var headers: [String: String]? {
        return ["X-Client-ID": "vultisig"]
    }
}
