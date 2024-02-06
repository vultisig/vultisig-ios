//
//  Chain.swift
//  VoltixApp

import Foundation
import SwiftData

@Model
final class Chain : ObservableObject {
    @Attribute(.unique) var name: String
    @Attribute(.unique) var ticker: String
    var signingKeyType: KeyType

    init(name: String, ticker: String, signingKeyType: KeyType) {
        self.name = name
        self.ticker = ticker
        self.signingKeyType = signingKeyType
    }

    static let THORChain = Chain(name: "THORChain", ticker: "RUNE", signingKeyType: KeyType.ECDSA)
    static let Solana = Chain(name:"Solana",ticker: "SOL",signingKeyType: KeyType.EdDSA)
}
