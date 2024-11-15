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

struct CosmosIbcDenomTraceDenomTrace: Codable {
    let path: String
    let baseDenom: String

    enum CodingKeys: String, CodingKey {
        case path
        case baseDenom = "base_denom"
    }
}

struct CosmosIbcDenomTraceErrorResponse: Codable {
    let code: Int
    let message: String
}
