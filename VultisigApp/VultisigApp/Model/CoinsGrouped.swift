//
//  CoinsGrouped.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-12.
//

import Foundation
import SwiftUI
import Combine

class GroupedChain: ObservableObject {
    let id: String
    let chain: Chain
    let address: String
    var logo: String
    var count: Int
    var coins: [Coin]

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
        // Try to find the actual native token first
        if let nativeToken = coins.first(where: { $0.isNativeToken }) {
            return nativeToken
        }
        
        // Fallback to first coin, with safety check
        guard let firstCoin = coins.first else {
            assertionFailure("GroupedChain.nativeCoin accessed with empty coins array")
            return Coin.example // Safe fallback to prevent crash
        }
        
        return firstCoin
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
