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
        switch self {
        case .getTransactionStatus(_, let chain):
            return URL(string: getBaseURL(for: chain))!
        }
    }

    var path: String {
        switch self {
        case .getTransactionStatus(let txHash, _):
            return "/api/tx/\(txHash)"
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

    private func getBaseURL(for chain: Chain) -> String {
        switch chain {
        case .bitcoin:
            return "https://mempool.space"
        case .litecoin:
            return "https://litecoinspace.org"
        case .bitcoinCash:
            return "https://blockchair.com/bitcoin-cash"
        case .dogecoin:
            return "https://dogechain.info"
        default:
            return "https://mempool.space"
        }
    }
}
