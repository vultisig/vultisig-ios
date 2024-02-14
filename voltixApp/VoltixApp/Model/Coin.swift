//
//  Coin.swift
//  VoltixApp

import Foundation
import SwiftData
import WalletCore

@Model
final class Coin {
    let chain: Chain
    @Attribute(.unique) let symbol: String
    let logo: String
    let address: String

    init(chain: Chain, symbol: String, logo: String, address: String) {
        self.chain = chain
        self.symbol = symbol
        self.logo = logo
        self.address = address
    }
}
