//
//  PolkadotTransactionStatusAPI.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

/// Polkadot Asset Hub transaction status API.
///
/// Queries the Vultisig node RPC proxy (`https://api.vultisig.com/dot/`) — the
/// same node `PolkadotService` broadcasts to — instead of an external indexer.
/// `author_pendingExtrinsics` returns the extrinsics still sitting in the node's
/// transaction pool, which is enough to tell a pending transfer from an included
/// one without an API-key-gated indexer.
enum PolkadotTransactionStatusAPI: TargetType {
    case pendingExtrinsics

    var baseURL: URL {
        URL(string: Endpoint.polkadotServiceRpc)!
    }

    var path: String {
        ""
    }

    var method: HTTPMethod {
        .post
    }

    var task: HTTPTask {
        switch self {
        case .pendingExtrinsics:
            let body: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "author_pendingExtrinsics",
                "params": []
            ]
            return .requestParameters(body, .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        ["Content-Type": "application/json"]
    }
}
