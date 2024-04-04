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
    case bscChain
    case bitcoin
    case bitcoinCash
    case litecoin
    case dogecoin
    case gaiaChain

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

    var thorAsset: String {
        switch self {
        case .thorChain: return "THOR.RUNE"
        case .ethereum: return "ETH.ETH"
        case .avalanche: return "AVAX.AVAX"
        case .bscChain: return "BSC.BNB"
        case .bitcoin: return "BTC.BTC"
        case .bitcoinCash: return "BCH.BCH"
        case .litecoin: return "LTC.LTC"
        case .dogecoin: return "DOGE.DOGE"
        case .gaiaChain: return "GAIA.ATOM"
        case .solana:
            fatalError()
        }
    }

    var isSwapSupported: Bool {
        switch self {
        case .thorChain, .ethereum, .avalanche, .bscChain, .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .gaiaChain:
            return true
        case .solana:
            return false
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
