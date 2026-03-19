//
//  CosmosIbcDenomTrace.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/11/24.
//

import Foundation

class CosmosIbcDenomTrace: Codable {
    let denomTrace: CosmosIbcDenomTraceDenomTrace?
    let error: CosmosIbcDenomTraceErrorResponse?
    let code: Int?
    let message: String?
    let details: [String]?
    let jsonrpc: String?

    enum CodingKeys: String, CodingKey {
        case denomTrace = "denom_trace"
        case error
        case code
        case message
        case details
        case jsonrpc
    }
}

struct CosmosIbcDenomTraceDenomTrace: Codable, Hashable {
    let path: String
    let baseDenom: String
    var height: String?

    enum CodingKeys: String, CodingKey {
        case path
        case baseDenom = "base_denom"
        case height
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
        hasher.combine(baseDenom)
        hasher.combine(height)
    }
}

struct CosmosIbcDenomTraceErrorResponse: Codable {
    let code: Int
    let message: String
}
