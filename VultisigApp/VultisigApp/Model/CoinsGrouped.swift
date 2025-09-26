//
//  CoinsGrouped.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-12.
//

import Foundation
import SwiftUI
import Combine

class GroupedChain: ObservableObject, Identifiable, Hashable {
    static func == (lhs: GroupedChain, rhs: GroupedChain) -> Bool {
        lhs.chain == rhs.chain
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(chain)
    }
    
    let id: String
    let chain: Chain
    let address: String
    var logo: String
    var count: Int
    var coins: [Coin]
    
    var truncatedAddress: String {
        address.prefix(4) + "..." + address.suffix(4)
    }

    var totalBalanceInFiatDecimal: Decimal {
        return coins.totalBalanceInFiatDecimal
    }

    var totalBalanceInFiatString: String {
        return coins.totalBalanceInFiatString
    }

    var name: String {
        return chain.name
    }

    var nativeCoin: Coin {
        return coins[0]
    }

    init(chain: Chain, address: String, logo: String, count: Int = 0, coins: [Coin]) {
        self.id = chain.name + "-" + address
        self.chain = chain
        self.address = address
        self.logo = logo
        self.count = count
        self.coins = coins
    }
    
    static var example = GroupedChain(chain: .bitcoin, address: "bc1psrjtwm7682v6nhx2...uwfgcfelrennd7pcvq", logo: "btc", count: 3, coins: [Coin.example])
}
