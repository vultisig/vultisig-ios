//
//  Chain.swift
//  VoltixApp

import Foundation
import SwiftData

enum Chain: String, Codable, Hashable, CaseIterable {
    case thorChain
    case solana
    case ethereum
    case avalanche
    case base
    case arbitrum
    case polygon
    case optimism
    case bscChain
    case bitcoin
    case bitcoinCash
    case litecoin
    case dogecoin
    case dash
    case gaiaChain
    case kujira
    case mayaChain
    
    enum MigrationKeys: String, CodingKey {
        case ticker
    }
    
    // TODO: Remove later after team have migrated
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = Chain(rawValue: value)!
            return
        } else {
            let container = try decoder.container(keyedBy: MigrationKeys.self)
            let ticker = try container.decode(String.self, forKey: .ticker)
            
            for chain in Chain.allCases where chain.ticker == ticker  {
                self = chain
                return
            }
        }
        
        fatalError("Migration failed")
    }
    
    var name: String {
        switch self {
        case .thorChain: return "THORChain"
        case .solana: return "Solana"
        case .ethereum: return "Ethereum"
        case .avalanche: return "Avalanche"
        case .bscChain: return "BSC"
        case .bitcoin: return "Bitcoin"
        case .bitcoinCash: return "Bitcoin-Cash"
        case .litecoin: return "Litecoin"
        case .dogecoin: return "Dogecoin"
        case .gaiaChain: return "Gaia"
        case .kujira: return "Kujira"
        case .dash: return "Dash"
        case .mayaChain: return "MayaChain"
        case .arbitrum: return "Arbitrum"
        case .base: return "Base"
        case .optimism: return "Optimism"
        case .polygon: return "Polygon"
        }
    }
    
    var ticker: String {
        switch self {
        case .thorChain: return "RUNE"
        case .solana: return "SOL"
        case .ethereum: return "ETH"
        case .avalanche: return "AVAX"
        case .bscChain: return "BNB"
        case .bitcoin: return "BTC"
        case .bitcoinCash: return "BCH"
        case .litecoin: return "LTC"
        case .dogecoin: return "DOGE"
        case .gaiaChain: return "UATOM"
        case .kujira: return "UKUJI"
        case .dash: return "DASH"
        case .mayaChain: return "CACAO"
        case .arbitrum: return "ARB"
        case .base: return "ETH" //Base does not have a coin
        case .optimism: return "OP"
        case .polygon: return "MATIC"
        }
    }
    
    var swapAsset: String {
        switch self {
        case .thorChain: return "THOR"
        case .ethereum: return "ETH"
        case .avalanche: return "AVAX"
        case .bscChain: return "BSC"
        case .bitcoin: return "BTC"
        case .bitcoinCash: return "BCH"
        case .litecoin: return "LTC"
        case .dogecoin: return "DOGE"
        case .gaiaChain: return "GAIA"
        case .kujira: return "KUJI"
        case .solana: return "SOL"
        case .dash: return "DASH"
        case .mayaChain: return "CACAO"
        case .arbitrum: return "ARB"
        case .base: return "ETH"
        case .optimism: return "OP"
        case .polygon: return "MATIC"
        }
    }
    
    var isSwapSupported: Bool {
        switch self {
        case .thorChain, .ethereum, .avalanche, .bscChain, .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .gaiaChain:
            return true
        case .solana, .dash, .kujira, .mayaChain,.arbitrum, .base, .optimism, .polygon:
            return false
        }
    }
    
    var signingKeyType: KeyType {
        switch self.chainType {
        case .Cosmos, .EVM, .THORChain, .UTXO:
            return .ECDSA
        case .Solana:
            return .EdDSA
        }
    }
    
    var chainType: ChainType {
        switch self {
        case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon:
            return .EVM
        case .thorChain,.mayaChain:
            return .THORChain
        case .solana:
            return .Solana
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
            return .UTXO
        case .gaiaChain, .kujira:
            return .Cosmos
        }
    }
}
