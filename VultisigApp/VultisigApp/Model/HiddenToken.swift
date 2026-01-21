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

    @Relationship(inverse: \Vault.hiddenTokens) var vault: Vault?

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

    private var normalizedTicker: String {
        ticker.lowercased()
    }

    private var normalizedContract: String {
        contractAddress.lowercased()
    }

    /// Check if this hidden token matches a CoinMeta
    func matches(_ coinMeta: CoinMeta) -> Bool {
        return chain.caseInsensitiveCompare(coinMeta.chain.rawValue) == .orderedSame &&
               normalizedTicker == coinMeta.ticker.lowercased() &&
               normalizedContract == coinMeta.contractAddress.lowercased()
    }
}

extension HiddenToken: Hashable {
    static func == (lhs: HiddenToken, rhs: HiddenToken) -> Bool {
        return lhs.chain.caseInsensitiveCompare(rhs.chain) == .orderedSame &&
               lhs.normalizedTicker == rhs.normalizedTicker &&
               lhs.normalizedContract == rhs.normalizedContract
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(chain.lowercased())
        hasher.combine(normalizedTicker)
        hasher.combine(normalizedContract)
    }
}
