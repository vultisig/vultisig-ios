//
//  Chain.swift
//  VoltixApp

import Foundation
import SwiftData

@Model
final class Chain {
    @Attribute(.unique) let name: String
    @Attribute(.unique) let ticker: String
    @Relationship(deleteRule:.cascade) var coins: [Coin]
    
    init(name: String, ticker: String, coins: [Coin]) {
        self.name = name
        self.ticker = ticker
        self.coins = coins
    }
}
