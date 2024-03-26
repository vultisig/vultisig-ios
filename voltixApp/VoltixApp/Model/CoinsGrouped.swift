//
//  CoinsGrouped.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-12.
//

import Foundation

class GroupedChain {
    let id: String
    let name: String
    let address: String
    var count: Int
    var coins: [Coin]
    
    init(name: String, address: String, count: Int = 0, coins: [Coin]) {
        self.id = name + "-" + address
        self.name = name
        self.address = address
        self.count = count
        self.coins = coins
    }
    
    static var example = GroupedChain(name: "Ethereum", address: "bc1psrjtwm7682v6nhx2...uwfgcfelrennd7pcvq", count: 3, coins: [Coin.example])
}
