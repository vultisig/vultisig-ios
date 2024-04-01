//
//  Chain.swift
//  VoltixApp

import Foundation
import SwiftData

class Chain: Codable, Hashable {
    var name: String
    var ticker: String
    var signingKeyType: KeyType
	var chainType: ChainType?
    
	init(name: String, ticker: String, signingKeyType: KeyType, chainType: ChainType) {
        self.name = name
        self.ticker = ticker
        self.signingKeyType = signingKeyType
		self.chainType = chainType
    }
    
    static func == (lhs: Chain, rhs: Chain) -> Bool {
		lhs.name == rhs.name && lhs.ticker == rhs.ticker && lhs.signingKeyType == rhs.signingKeyType && lhs.chainType == rhs.chainType
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(ticker)
        hasher.combine(signingKeyType)
		hasher.combine(chainType)
    }
    
	static let THORChain = Chain(name: "THORChain", ticker: "RUNE", signingKeyType: KeyType.ECDSA, chainType: .THORChain)
    static let Solana = Chain(name: "Solana", ticker: "SOL", signingKeyType: KeyType.EdDSA, chainType: .Solana)
	static let Ethereum = Chain(name: "Ethereum", ticker: "ETH", signingKeyType: .ECDSA, chainType: .EVM)
    static let Avalache = Chain(name: "Avalache", ticker: "AVAX", signingKeyType: .ECDSA, chainType: .EVM)
    static let BSCChain = Chain(name: "BSC", ticker: "BNB", signingKeyType: .ECDSA, chainType: .EVM)
	static let Bitcoin = Chain(name: "Bitcoin", ticker: "BTC", signingKeyType: .ECDSA, chainType: .UTXO)
    static let BitcoinCash = Chain(name: "Bitcoin-Cash", ticker: "BCH", signingKeyType: .ECDSA, chainType: .UTXO)
    static let Litecoin = Chain(name: "Litecoin", ticker: "LTC", signingKeyType: .ECDSA, chainType: .UTXO)
    static let Dogecoin = Chain(name: "Dogecoin", ticker: "DOGE", signingKeyType: .ECDSA, chainType: .UTXO)
    static let GaiaChain = Chain(name: "Gaia", ticker: "ATOM", signingKeyType: .ECDSA, chainType: .Cosmos)
}
