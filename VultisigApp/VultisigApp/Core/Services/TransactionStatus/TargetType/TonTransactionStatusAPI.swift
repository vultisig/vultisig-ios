//
//  TonTransactionStatusAPI.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

/// TON Transaction Status API
/// - Uses TON Center API v3 `/api/v3/transactionsByMessage` endpoint
/// - Searches for transactions by incoming message hash
/// - Message hash can be in hex, base64, or base64url format
enum TonTransactionStatusAPI: TargetType {
    case getTransactionsByMessage(msgHash: String)

    var baseURL: URL {
        URL(string: "https://api.vultisig.com/ton")!
    }

    var path: String {
        "/v3/transactionsByMessage"
    }

    var method: HTTPMethod {
        .get
    }

    var task: HTTPTask {
        switch self {
        case .getTransactionsByMessage(let msgHash):
            // direction=in means incoming message
            let params: [String: String] = [
                "direction": "in",
                "msg_hash": msgHash
            ]
            return .requestParameters(params, .urlEncoding)
        }
    }

    var headers: [String: String]? {
        ["Content-Type": "application/json"]
    }
}
