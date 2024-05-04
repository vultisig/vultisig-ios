//
//  CoinsGrouped.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-12.
//

import Foundation

class GroupedChain {
    let id: String
    let chain: Chain
    let address: String
    var logo: String
    var count: Int
    var coins: [Coin]
    var order: Int = 0

    var name: String {
        return chain.name
    }

    init(chain: Chain, address: String, logo: String, count: Int = 0, coins: [Coin]) {
        self.id = chain.name + "-" + address
        self.chain = chain
        self.address = address
        self.logo = logo
        self.count = count
        self.coins = coins
    }
    
    func setOrder(_ index: Int) {
        order = index
    }
    
    static var example = GroupedChain(chain: .ethereum, address: "bc1psrjtwm7682v6nhx2...uwfgcfelrennd7pcvq", logo: "btc", count: 3, coins: [Coin.example])
}
