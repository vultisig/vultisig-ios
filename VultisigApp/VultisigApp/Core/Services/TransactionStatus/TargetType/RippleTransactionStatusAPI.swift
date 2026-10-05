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
    ///
    /// `ledgerRange` bounds the search so a `txnNotFound` answer reports
    /// `searched_all`. A transaction found anywhere is still returned.
    case getTx(txHash: String, host: URL, ledgerRange: ClosedRange<Int>? = nil)

    var baseURL: URL {
        switch self {
        case .getTx(_, let host, _):
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
        case .getTx(let txHash, _, let ledgerRange):
            // XRP Ledger JSON-RPC format
            var params: [String: Any] = [
                "transaction": txHash,
                "binary": false,
                "api_version": 2
            ]
            if let ledgerRange {
                params["min_ledger"] = ledgerRange.lowerBound
                params["max_ledger"] = ledgerRange.upperBound
            }
            let body: [String: Any] = [
                "method": "tx",
                "params": [params]
            ]
            return .requestParameters(body, .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        ["Content-Type": "application/json"]
    }
}
