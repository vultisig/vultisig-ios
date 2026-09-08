//
//  TronTransactionStatusAPI.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

enum TronTransactionStatusAPI: TargetType {
    case getTransactionInfo(txHash: String)
    /// The signed transaction as the node holds it. Unlike the info endpoint
    /// it carries `raw_data.expiration`, which is the only way to tell an
    /// unconfirmed transaction from one that can never be included.
    case getTransactionById(txHash: String)
    /// Head block, read for its timestamp — TRON validates `expiration`
    /// against block time, not against the device clock.
    case getNowBlock

    var baseURL: URL {
        URL(string: Endpoint.tronWalletApi)!
    }

    var path: String {
        switch self {
        case .getTransactionInfo:
            return "/wallet/gettransactioninfobyid"
        case .getTransactionById:
            return "/wallet/gettransactionbyid"
        case .getNowBlock:
            return "/wallet/getnowblock"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getTransactionInfo, .getTransactionById:
            return .post
        case .getNowBlock:
            return .get
        }
    }

    var task: HTTPTask {
        switch self {
        case .getTransactionInfo(let txHash), .getTransactionById(let txHash):
            let body: [String: Any] = [
                "value": txHash,
                "visible": true
            ]
            return .requestParameters(body, .jsonEncoding)
        case .getNowBlock:
            return .requestPlain
        }
    }

    var headers: [String: String]? {
        [
            "accept": "application/json",
            "content-type": "application/json"
        ]
    }
}
