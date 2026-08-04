//
//  SuiAPI.swift
//  VultisigApp
//

import Foundation

struct SuiAPI: TargetType {
    enum Endpoint {
        case coinMetadata(coinType: String)
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
        }
    }
}
