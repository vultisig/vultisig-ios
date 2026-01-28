//
//  PolkadotTransactionStatusAPI.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

/// Polkadot Transaction Status API
/// - Uses Subscan API format for AssetHub Polkadot
/// - Endpoint: https://assethub-polkadot.api.subscan.io/api/scan/extrinsic
enum PolkadotTransactionStatusAPI: TargetType {
    case getExtrinsicByHash(extrinsicHash: String)

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
        case .getExtrinsicByHash(let extrinsicHash):
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
