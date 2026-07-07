//
//  RippleTransactionStatusAPI.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

enum RippleTransactionStatusAPI: TargetType {
    /// The resolved XRPL host (override-aware) is baked in by the provider so
    /// the status lookup uses the SAME host as broadcast/reads — a same-host
    /// retry then stays on the user's configured node, not the default pool.
    case getTx(txHash: String, host: URL)

    var baseURL: URL {
        switch self {
        case .getTx(_, let host):
            return host
        }
    }

    var path: String {
        "/"
    }

    var method: HTTPMethod {
        .post
    }

    var task: HTTPTask {
        switch self {
        case .getTx(let txHash, _):
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
