//
//  SuiAPI.swift
//  VultisigApp
//

import Foundation

struct SuiAPI: TargetType {
    enum Endpoint {
        case coinMetadata(coinType: String)
        case allBalances(address: String)
        case allCoins(address: String, cursor: String?)
    }

    let baseURL: URL
    let endpoint: Endpoint

    var path: String { "" }

    var method: HTTPMethod { .post }

    var task: HTTPTask {
        switch endpoint {
        case .coinMetadata(let coinType):
            return .requestParameters(
                [
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "suix_getCoinMetadata",
                    "params": [coinType]
                ],
                .jsonEncoding
            )
        case .allBalances(let address):
            return .requestParameters(
                [
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "suix_getAllBalances",
                    "params": [address]
                ],
                .jsonEncoding
            )
        case .allCoins(let address, let cursor):
            let params: [Any] = [address, cursor ?? NSNull()]
            return .requestParameters(
                [
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "suix_getAllCoins",
                    "params": params
                ],
                .jsonEncoding
            )
        }
    }
}
