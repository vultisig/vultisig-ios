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
/// Substrate nodes have no "get extrinsic by hash" RPC, so inclusion is proven
/// by reading blocks (`chain_getBlock`) and matching the extrinsic hash; passing
/// no block hash returns the current best-head block to start the walk from.
enum PolkadotTransactionStatusAPI: TargetType {
    case getBlock(blockHash: String?)

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
        case .getBlock(let blockHash):
            let params: [Any] = blockHash.map { [$0] } ?? []
            let body: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "chain_getBlock",
                "params": params
            ]
            return .requestParameters(body, .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        ["Content-Type": "application/json"]
    }
}
