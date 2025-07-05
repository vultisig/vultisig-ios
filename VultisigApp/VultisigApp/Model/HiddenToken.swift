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
    var chain: String
    var ticker: String
    var contractAddress: String
    var hiddenAt: Date
    
    init(chain: Chain, ticker: String, contractAddress: String) {
        self.chain = chain.rawValue
        self.ticker = ticker
        self.contractAddress = contractAddress
        self.hiddenAt = Date()
    }
    
    convenience init(coinMeta: CoinMeta) {
        self.init(chain: coinMeta.chain, ticker: coinMeta.ticker, contractAddress: coinMeta.contractAddress)
    }
    
    convenience init(coin: Coin) {
        self.init(chain: coin.chain, ticker: coin.ticker, contractAddress: coin.contractAddress)
    }
    
    /// Unique identifier for matching tokens
    var identifier: String {
        return "\(chain)-\(ticker)-\(contractAddress)"
    }
    
    /// Check if this hidden token matches a CoinMeta
    func matches(_ coinMeta: CoinMeta) -> Bool {
        return chain == coinMeta.chain.rawValue &&
               ticker == coinMeta.ticker &&
               contractAddress == coinMeta.contractAddress
    }
}

extension HiddenToken: Hashable {
    static func == (lhs: HiddenToken, rhs: HiddenToken) -> Bool {
        return lhs.chain == rhs.chain &&
               lhs.ticker == rhs.ticker &&
               lhs.contractAddress == rhs.contractAddress
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(chain)
        hasher.combine(ticker)
        hasher.combine(contractAddress)
    }
} 