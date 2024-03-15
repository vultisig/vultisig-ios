//
//  TokenInfo.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import Foundation

class EthTokenInfo: Codable {
    let address: String
    let name: String
    let decimals: String
    let symbol: String
    let totalSupply: String
    let owner: String
    let lastUpdated: Int
    let price: ETHInfoPrice
}
