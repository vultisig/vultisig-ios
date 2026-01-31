//
//  SolanaTransactionStatusAPI.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation

enum SolanaTransactionStatusAPI: TargetType {
    case getSignatureStatuses(txHash: String)

    var baseURL: URL {
        URL(string: Endpoint.solanaServiceRpc)!
    }

    var path: String {
        ""  // RPC endpoint doesn't use path
    }

    var method: HTTPMethod {
        .post
    }

    var task: HTTPTask {
        switch self {
        case .getSignatureStatuses(let txHash):
            let body: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "getSignatureStatuses",
                "params": [
                    [txHash],
                    ["searchTransactionHistory": true]
                ]
            ]
            return .requestParameters(body, .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        ["Content-Type": "application/json"]
    }
}
