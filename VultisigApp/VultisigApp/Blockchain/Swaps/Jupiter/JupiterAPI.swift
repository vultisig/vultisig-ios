//
//  JupiterAPI.swift
//  VultisigApp
//
//  TargetType definitions for Jupiter's Solana swap surface, routed through the
//  Vultisig backend proxy (`api.vultisig.com/jup`). The proxy forwards
//  `/swap/v1/quote` (GET) and `/swap/v1/swap` (POST) 1:1. Same proxy pattern
//  as the SwapKit / 1inch integrations.
//

import Foundation

enum JupiterAPI {
    case quote(JupiterQuoteParams)
    /// Pre-serialized swap request body. The body embeds the verbatim `/quote`
    /// response object under `quoteResponse`, so it is assembled with
    /// `JSONSerialization` in `JupiterService` and forwarded as raw data rather
    /// than via a lossy Codable round-trip.
    case swap(body: Data)
}

extension JupiterAPI: TargetType {
    var baseURL: URL {
        URL(string: "https://api.vultisig.com/jup")!
    }

    var path: String {
        switch self {
        case .quote:
            return "/swap/v1/quote"
        case .swap:
            return "/swap/v1/swap"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .quote:
            return .get
        case .swap:
            return .post
        }
    }

    var task: HTTPTask {
        switch self {
        case .quote(let params):
            return .requestParameters(params.queryItems, .urlEncoding)
        case .swap(let body):
            return .requestData(body)
        }
    }

    var headers: [String: String]? {
        [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
    }
}
