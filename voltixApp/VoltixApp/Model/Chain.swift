//
//  Chain.swift
//  VoltixApp

import Foundation
import SwiftData

enum Chain: String, Codable, Hashable {
    case thorChain
    case solana
    case ethereum
    case avalanche
    case bscChain
    case bitcoin
    case bitcoinCash
    case litecoin
    case dogecoin
    case gaiaChain

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
        }
    }

    var signingKeyType: KeyType {
        switch self {
        case .thorChain, .ethereum, .avalanche, .bscChain, .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .gaiaChain:
            return .ECDSA
        case .solana:
            return .EdDSA
        }
    }

    var chainType: ChainType {
        switch self {
        case .ethereum, .avalanche, .bscChain:
            return .EVM
        case .thorChain:
            return .THORChain
        case .solana:
            return .Solana
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin:
            return .UTXO
        case .gaiaChain:
            return .Cosmos
        }
    }
}
