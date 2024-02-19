//
//  Coin.swift
//  VoltixApp

import Foundation
import SwiftData
import WalletCore


struct Coin : Codable,Hashable {
    let chain: Chain
    let ticker: String
    let logo: String
    let address: String
    init(chain: Chain, ticker: String, logo: String, address: String) {
        self.chain = chain
        self.ticker = ticker
        self.logo = logo
        self.address = address
    }
}
