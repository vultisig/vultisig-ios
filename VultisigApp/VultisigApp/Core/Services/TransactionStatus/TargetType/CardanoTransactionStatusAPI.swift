//
//  CardanoTransactionStatusAPI.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

/// Cardano Transaction Status API
/// - Uses Koios API POST /tx_status endpoint
/// - Request body: {"_tx_hashes": ["hash1", "hash2"]}
/// - Returns array of {tx_hash, num_confirmations}
enum CardanoTransactionStatusAPI: TargetType {
    case getTxStatus(txHash: String)

    var baseURL: URL {
        URL(string: Endpoint.cardanoServiceRpc)!
    }

    var path: String {
        "/tx_status"
    }

    var method: HTTPMethod {
        .post
    }

    var task: HTTPTask {
        switch self {
        case .getTxStatus(let txHash):
            // Koios API expects array of tx hashes
            let body: [String: Any] = [
                "_tx_hashes": [txHash]
            ]
            return .requestParameters(body, .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        ["Content-Type": "application/json"]
    }
}
