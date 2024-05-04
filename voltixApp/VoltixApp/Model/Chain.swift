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
    case blast
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
    case cronosChain
    case sui
    case polkadot
    
    enum MigrationKeys: String, CodingKey {
        case ticker
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
        case .blast: return "Blast"
        case .cronosChain: return "CronosChain"
        case .sui: return "Sui"
        case .polkadot: return "Polkadot"
            
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
        case .base: return "BASE" //Base does not have a coin
        case .optimism: return "OP"
        case .polygon: return "MATIC"
        case .blast: return "BLAST"
        case .cronosChain: return "CRO"
        case .sui: return "SUI"
        case .polkadot: return "DOT"
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
        case .base: return "BASE"
        case .optimism: return "OP"
        case .polygon: return "MATIC"
        case .blast: return "BLAST"
        case .cronosChain: return "CRO"
        case .sui: return "SUI"
        case .polkadot: return "DOT"
        }
    }
    
    var isSwapSupported: Bool {
        switch self {
        case .thorChain, .ethereum, .avalanche, .bscChain, .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .gaiaChain:
            return true
        case .solana, .dash, .kujira, .mayaChain,.arbitrum, .base, .optimism, .polygon, .blast, .cronosChain, .polkadot, .sui:
            return false
        }
    }
    
    var signingKeyType: KeyType {
        switch self.chainType {
        case .Cosmos, .EVM, .THORChain, .UTXO:
            return .ECDSA
        case .Solana, .Polkadot, .Sui:
            return .EdDSA
        }
    }
    
    var chainType: ChainType {
        switch self {
        case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .blast, .cronosChain:
            return .EVM
        case .thorChain,.mayaChain:
            return .THORChain
        case .solana:
            return .Solana
        case .sui:
            return .Sui
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
            return .UTXO
        case .gaiaChain, .kujira:
            return .Cosmos
        case .polkadot:
            return .Polkadot
        }
    }

    var logo: String {
        switch self {
        case .thorChain:
            return "rune"
        case .solana:
            return "solana"
        case .ethereum:
            return "eth"
        case .avalanche:
            return "avax"
        case .base:
            return "eth_base"
        case .blast:
            return "eth_blast"
        case .arbitrum:
            return "arbitrum"
        case .polygon:
            return "polygon"
        case .optimism:
            return "optimism"
        case .bscChain:
            return "bsc"
        case .bitcoin:
            return "btc"
        case .bitcoinCash:
            return "bch"
        case .litecoin:
            return "ltc"
        case .dogecoin:
            return "doge"
        case .dash:
            return "dash"
        case .gaiaChain:
            return "atom"
        case .kujira:
            return "kuji"
        case .mayaChain:
            return "maya"
        case .cronosChain:
            return "cro"
        case .sui:
            return "sui"
        case .polkadot:
            return "polkadot"
        }
    }
}
