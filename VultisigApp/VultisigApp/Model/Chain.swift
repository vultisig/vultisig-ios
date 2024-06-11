//
//  Chain.swift
//  VultisigApp

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
    case zksync
    
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
        case .zksync: return "Zksync"
        }
    }
    var feeUnit: String{
        switch self {
        case .thorChain: return "RUNE"
        case .solana: return "SOL"
        case .ethereum,.avalanche,.base,.blast,.arbitrum,.polygon,.optimism,.bscChain,.cronosChain, .zksync: return "Gwei"
        case .bitcoin: return "BTC/vbyte"
        case .bitcoinCash: return "BCH/vbyte"
        case .litecoin: return "LTC/vbyte"
        case .dogecoin: return "DOGE/vbyte"
        case .dash: return "DASH/vbyte"
        case .gaiaChain: return "uatom"
        case .kujira: return "ukuji"
        case .mayaChain: return "CACAO"
        case .sui: return "SUI"
        case .polkadot: return "DOT"
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
        case .zksync: return "ZK"
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
        case .mayaChain: return "MAYA"
        case .arbitrum: return "ARB"
        case .base: return "BASE"
        case .optimism: return "OP"
        case .polygon: return "MATIC"
        case .blast: return "BLAST"
        case .cronosChain: return "CRO"
        case .sui: return "SUI"
        case .polkadot: return "DOT"
        case .zksync: return "ZK"
        }
    }
    
    var isSwapSupported: Bool {
        switch self {
        case .thorChain, .mayaChain, .ethereum, .avalanche, .bscChain, .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .gaiaChain:
            return true
        case .solana, .dash, .kujira,.arbitrum, .base, .optimism, .polygon, .blast, .cronosChain, .polkadot, .sui, .zksync:
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
        case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .blast, .cronosChain, .zksync:
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
        case .zksync:
            return "eth_zksync"
        }
    }
    
    var chainID: Int? {
        switch self {
        case .ethereum:
            return 1
        case .avalanche:
            return 43114
        case .base:
            return 8453
        case .blast:
            return 238
        case .arbitrum:
            return 42161
        case .polygon:
            return 137
        case .optimism:
            return 10
        case .bscChain:
            return 56
        case .cronosChain:
            return 25
        case .zksync:
            return 324
        case .solana, .thorChain, .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash, .gaiaChain, .kujira, .mayaChain, .sui, .polkadot:
            return nil
        }
    }

    var coingeckoId: String {
        switch self {
        case .ethereum:
            return "eth"
        case .avalanche:
            return "avax"
        case .base:
            return "base"
        case .blast:
            return "blast"
        case .arbitrum:
            return "arbitrum"
        case .polygon:
            return "polygon_pos"
        case .optimism:
            return "optimism"
        case .bscChain:
            return "bsc"
        case .cronosChain:
            return "cro"
        case .solana, .thorChain, .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash, .gaiaChain, .kujira, .mayaChain, .sui, .polkadot, .zksync:
            return .empty
        }
    }
}
