//
//  HiddenToken.swift
//  VultisigApp
//
//  Created by Assistant on 2024-01-03.
//

import Foundation
import SwiftData

@Model
class HiddenToken {
    var coinMeta: CoinMeta
    var hiddenAt: Date
    
    init(coinMeta: CoinMeta) {
        self.coinMeta = coinMeta
        self.hiddenAt = Date()
    }
    
    convenience init(coin: Coin) {
        self.init(coinMeta: coin.toCoinMeta())
    }
    
    /// Unique identifier for matching tokens
    var identifier: String {
        return "\(coinMeta.chain.rawValue)-\(coinMeta.ticker)-\(coinMeta.contractAddress)"
    }
}

extension HiddenToken: Hashable {
    static func == (lhs: HiddenToken, rhs: HiddenToken) -> Bool {
        return lhs.coinMeta == rhs.coinMeta
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(coinMeta)
    }
} 