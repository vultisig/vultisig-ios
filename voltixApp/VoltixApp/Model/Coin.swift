//
//  Coin.swift
//  VoltixApp

import Foundation
import SwiftData

@Model
final class Coin {
    let chain: Chain
    @Attribute(.unique) let symbol: String
    let logo: String
    
    init(chain: Chain, symbol: String, logo: String) {
        self.chain = chain
        self.symbol = symbol
        self.logo = logo
    }
}
