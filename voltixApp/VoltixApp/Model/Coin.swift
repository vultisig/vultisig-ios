//
//  Coin.swift
//  VoltixApp

import Foundation
import SwiftData

struct Coin: Codable, Hashable {
    let chain: Chain
    let ticker: String
    let logo: String
    let address: String
    @DecodableDefault.EmptyString var hexPublicKey: String
    @DecodableDefault.EmptyString var feeUnit: String

    init(chain: Chain, ticker: String, logo: String, address: String, hexPublicKey: String, feeUnit: String) {
        self.chain = chain
        self.ticker = ticker
        self.logo = logo
        self.address = address
        self.hexPublicKey = hexPublicKey
        self.feeUnit = feeUnit
    }

}
