//
//  Chain.swift
//  VoltixApp

import Foundation
import SwiftData

struct Chain : Codable,Hashable {
    var name: String
    var ticker: String
    var signingKeyType: KeyType

    init(name: String, ticker: String, signingKeyType: KeyType) {
        self.name = name
        self.ticker = ticker
        self.signingKeyType = signingKeyType
    }

    static let THORChain = Chain(name: "THORChain", ticker: "RUNE", signingKeyType: KeyType.ECDSA)
    static let Solana = Chain(name:"Solana",ticker: "SOL",signingKeyType: KeyType.EdDSA)
    static let Bitcoin = Chain(name:"Bitcoin",ticker: "BTC",signingKeyType: .ECDSA)
    //TODO: this is a mock
    static let Ethereum = Chain(name:"Ethereum",ticker: "ETH",signingKeyType: .ECDSA)
}
