//
//  TronTransactionStatusAPI.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

enum TronTransactionStatusAPI: TargetType {
    case getTransactionInfo(txHash: String)
    /// Carries `raw_data.expiration`, which the info endpoint does not.
    case getTransactionById(txHash: String)
    /// Read for its timestamp: TRON validates `expiration` against block time.
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
