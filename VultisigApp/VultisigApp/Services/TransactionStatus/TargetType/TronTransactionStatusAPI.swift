//
//  TronTransactionStatusAPI.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

enum TronTransactionStatusAPI: TargetType {
    case getTransactionInfo(txHash: String)

    var baseURL: URL {
        URL(string: Endpoint.tronWalletApi)!
    }

    var path: String {
        switch self {
        case .getTransactionInfo:
            return "/wallet/gettransactioninfobyid"
        }
    }

    var method: HTTPMethod {
        .post
    }

    var task: HTTPTask {
        switch self {
        case .getTransactionInfo(let txHash):
            let body: [String: Any] = [
                "value": txHash,
                "visible": true
            ]
            return .requestParameters(body, .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        [
            "accept": "application/json",
            "content-type": "application/json"
        ]
    }
}
