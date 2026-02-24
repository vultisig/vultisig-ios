//
//  THORChainTransactionStatusAPI.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

enum THORChainTransactionStatusAPI: TargetType {
    case getActions(txHash: String, chain: Chain)

    var baseURL: URL {
        switch self {
        case .getActions(_, let chain):
            let urlString: String
            if chain == .mayaChain {
                urlString = Endpoint.mayachainMidgard
            } else if chain == .thorChainChainnet {
                urlString = "https://chainnet-thornode.thorchain.network"
            } else if chain == .thorChainStagenet2 {
                urlString = "https://stagenet-thornode.ninerealms.com"
            } else {
                urlString = Endpoint.thorchainMidgard
            }
            return URL(string: urlString)!
        }
    }

    var path: String {
        "/v2/actions"
    }

    var method: HTTPMethod {
        .get
    }

    var task: HTTPTask {
        switch self {
        case .getActions(let txHash, _):
            // Query actions by transaction ID
            let params: [String: String] = ["txid": txHash]
            return .requestParameters(params, .urlEncoding)
        }
    }

    var headers: [String: String]? {
        ["Content-Type": "application/json"]
    }
}
