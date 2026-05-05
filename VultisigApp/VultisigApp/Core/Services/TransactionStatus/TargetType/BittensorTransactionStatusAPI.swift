//
//  BittensorTransactionStatusAPI.swift
//  VultisigApp
//

import Foundation

/// Bittensor extrinsic status — proxied through the Vultisig API
/// (`https://api.vultisig.com/tao-tx/v1?hash=…`), which itself wraps the
/// public Taostats API.
enum BittensorTransactionStatusAPI: TargetType {
    case getExtrinsic(txHash: String)

    var baseURL: URL {
        URL(string: "https://api.vultisig.com")!
    }

    var path: String {
        "/tao-tx/v1"
    }

    var method: HTTPMethod {
        .get
    }

    var task: HTTPTask {
        switch self {
        case .getExtrinsic(let txHash):
            return .requestParameters(["hash": txHash], .urlEncoding)
        }
    }

    var headers: [String: String]? {
        ["Content-Type": "application/json"]
    }
}
