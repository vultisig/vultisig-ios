//
//  SuiTransactionStatusAPI.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

enum SuiTransactionStatusAPI: TargetType {
    /// The resolved Sui host (override-aware) is baked in by the provider so the
    /// status lookup queries the SAME node that broadcast the transaction. A
    /// custom node and the default host do not necessarily share a view of a
    /// just-submitted digest, so polling the default while broadcasting to an
    /// override reports a live transaction as `notFound`.
    case getTransactionBlock(txHash: String, host: URL)

    var baseURL: URL {
        switch self {
        case .getTransactionBlock(_, let host):
            return host
        }
    }

    var path: String {
        ""  // RPC endpoint doesn't use path
    }

    var method: HTTPMethod {
        .post
    }

    var task: HTTPTask {
        switch self {
        case .getTransactionBlock(let txHash, _):
            let body: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_getTransactionBlock",
                "params": [
                    txHash,
                    ["showEffects": true, "showEvents": false]
                ]
            ]
            return .requestParameters(body, .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        ["Content-Type": "application/json"]
    }
}
