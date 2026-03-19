//
//  UTXOTransactionStatusAPI.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation

enum UTXOTransactionStatusAPI: TargetType {
    case getTransactionStatus(txHash: String, chain: Chain)

    var baseURL: URL {
        URL(string: "https://api.vultisig.com")!
    }

    var path: String {
        switch self {
        case .getTransactionStatus(let txHash, let chain):
            // Use proxy for Blockchair API
            let chainName = chain.name.lowercased()
            return "/blockchair/\(chainName)/dashboards/transaction/\(txHash)"
        }
    }

    var method: HTTPMethod {
        .get
    }

    var task: HTTPTask {
        .requestPlain
    }

    var headers: [String: String]? {
        ["Content-Type": "application/json"]
    }
}
