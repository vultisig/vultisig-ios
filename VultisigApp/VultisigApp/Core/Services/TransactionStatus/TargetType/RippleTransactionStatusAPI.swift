//
//  RippleTransactionStatusAPI.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

enum RippleTransactionStatusAPI: TargetType {
    case getTx(txHash: String)

    var baseURL: URL {
        URL(string: Endpoint.rippleServiceRpc)!
    }

    var path: String {
        ""  // RPC endpoint doesn't use path
    }

    var method: HTTPMethod {
        .post
    }

    var task: HTTPTask {
        switch self {
        case .getTx(let txHash):
            // XRP Ledger JSON-RPC format
            let body: [String: Any] = [
                "method": "tx",
                "params": [
                    [
                        "transaction": txHash,
                        "binary": false,
                        "api_version": 2
                    ]
                ]
            ]
            return .requestParameters(body, .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        ["Content-Type": "application/json"]
    }
}
