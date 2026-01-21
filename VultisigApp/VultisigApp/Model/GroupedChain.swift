//
//  CoinsGrouped.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-12.
//

import Foundation

class GroupedChain {
    let name: String
    let address: String
    var count: Int
    var coins: [Coin]

    init(name: String, address: String, count: Int = 0, coins: [Coin]) {
        self.name = name
        self.address = address
        self.count = count
        self.coins = coins
    }
}
