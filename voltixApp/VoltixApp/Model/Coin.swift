//
//  Coin.swift
//  VoltixApp

import Foundation
import SwiftData

class Coin: Codable, Hashable {
    let chain: Chain
    let ticker: String
    let logo: String
    let address: String
    
    @DecodableDefault.EmptyString var contractAddress: String
    @DecodableDefault.EmptyString var hexPublicKey: String
    @DecodableDefault.EmptyString var feeUnit: String
    
    init(chain: Chain, ticker: String, logo: String, address: String, hexPublicKey: String, feeUnit: String, contractAddress: String?) {
        self.chain = chain
        self.ticker = ticker
        self.logo = logo
        self.address = address
        self.hexPublicKey = hexPublicKey
        self.feeUnit = feeUnit
        self.contractAddress = contractAddress ?? ""
    }
    
    static func == (lhs: Coin, rhs: Coin) -> Bool {
        lhs.chain == rhs.chain && lhs.ticker == rhs.ticker && lhs.logo == rhs.logo && lhs.address == rhs.address
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(chain)
        hasher.combine(ticker)
        hasher.combine(logo)
        hasher.combine(address)
    }
    
    static let example = Coin(chain: Chain.Bitcoin, ticker: "btc", logo: "BitcoinLogo", address: "bc1psrjtwm7682v6nhx2...uwfgcfelrennd7pcvq", hexPublicKey: "HexUnit", feeUnit: "fee", contractAddress: "address")
}
