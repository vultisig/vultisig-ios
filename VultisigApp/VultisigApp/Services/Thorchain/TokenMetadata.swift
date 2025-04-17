//
//  TokenMetadata.swift
//  VultisigApp
//
//  Created by Johnny Luo on 17/4/2025.
//

struct TokenMetadata : Codable {
    let chain: String
    let ticker: String
    let symbol: String
    let decimals: Int
    let logo: String
}
