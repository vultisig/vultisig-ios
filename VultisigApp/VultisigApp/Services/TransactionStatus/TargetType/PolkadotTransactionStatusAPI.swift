//
//  PolkadotTransactionStatusAPI.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

/// Polkadot Transaction Status API
/// - Uses Subscan API format
/// - Currently: https://polkadot.api.subscan.io/api/scan/extrinsic (public API)
/// - TODO: Switch to Vultisig proxy once ready: https://api.vultisig.com/dot/api/scan/extrinsic
enum PolkadotTransactionStatusAPI: TargetType {
    case getExtrinsic(extrinsicHash: String)

    var baseURL: URL {
        URL(string: Endpoint.polkadotTransactionStatusRpc)!
    }

    var path: String {
        "api/scan/extrinsic"
    }

    var method: HTTPMethod {
        .post
    }

    var task: HTTPTask {
        switch self {
        case .getExtrinsic(let extrinsicHash):
            // Subscan API format: query by extrinsic hash
            let body: [String: Any] = [
                "hash": extrinsicHash
            ]
            return .requestParameters(body, .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        ["Content-Type": "application/json"]
    }
}
