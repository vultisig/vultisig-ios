//
//  TokenInfo.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 02/06/24.
//

import Foundation

struct TokenInfo: Decodable {
    let address: String
    let decimals: String
    let name: String
    let owner: String
    let symbol: String
    let totalSupply: String
    let holdersCount: Int
    let website: String
    let image: String
}

struct Token: Decodable {
    let tokenInfo: TokenInfo
    let balance: Int
    let rawBalance: String
}
