//
//  SuiTransactionStatusAPI.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

enum SuiTransactionStatusAPI: TargetType {
    case getTransactionBlock(txHash: String)

    var baseURL: URL {
        URL(string: Endpoint.suiServiceRpc)!
    }

    var path: String {
        ""  // RPC endpoint doesn't use path
    }

    var method: HTTPMethod {
        .post
    }

    var task: HTTPTask {
        switch self {
        case .getTransactionBlock(let txHash):
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
