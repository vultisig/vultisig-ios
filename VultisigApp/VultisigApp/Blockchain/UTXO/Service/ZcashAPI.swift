//
//  ZcashAPI.swift
//  VultisigApp
//

import Foundation

/// Zcash JSON-RPC endpoints proxied through `api.vultisig.com/zcash`.
enum ZcashAPI: TargetType {
    /// `getblockchaininfo` — used to read the active ZIP-243 consensus branch id
    /// (`consensus.nextblock`).
    case getBlockchainInfo

    var baseURL: URL {
        URL(string: "https://api.vultisig.com")!
    }

    var path: String {
        "/zcash/"
    }

    var method: HTTPMethod {
        .post
    }

    var task: HTTPTask {
        switch self {
        case .getBlockchainInfo:
            let body: [String: Any] = [
                "jsonrpc": "1.0",
                "id": "vultisig",
                "method": "getblockchaininfo",
                "params": [String]()
            ]
            return .requestParameters(body, .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        ["Content-Type": "application/json"]
    }
}
