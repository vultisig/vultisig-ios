//
//  Chain.swift
//  VultisigApp

import Foundation
import SwiftData
import WalletCore

enum Chain: String, Codable, Hashable, CaseIterable {
    case thorChain
    case thorChainStagenet
    case solana
    case ethereum
    case avalanche
    case base
    case blast
    case arbitrum
    case polygon
    case polygonV2
    case optimism
    case bscChain
    case bitcoin
    case bitcoinCash
    case litecoin
    case dogecoin
    case dash
    case cardano
    case gaiaChain
    case kujira
    case mayaChain
    case cronosChain
    case sui
    case polkadot
    case zksync
    case dydx
    case ton
    case osmosis
    case terra
    case terraClassic
    case noble
    case ripple
    case akash
    case tron
    case ethereumSepolia
    case zcash
    case mantle
    case hyperliquid
    case sei
    
    enum MigrationKeys: String, CodingKey {
        case ticker
    }
    
    var name: String {
        switch self {
        case .thorChain: return "THORChain"
        case .thorChainStagenet: return "THORChain-Stagenet"
        case .solana: return "Solana"
        case .ethereum: return "Ethereum"
        case .avalanche: return "Avalanche"
        case .bscChain: return "BSC"
        case .bitcoin: return "Bitcoin"
        case .bitcoinCash: return "Bitcoin-Cash"
        case .litecoin: return "Litecoin"
        case .dogecoin: return "Dogecoin"
        case .gaiaChain: return "Cosmos"
        case .kujira: return "Kujira"
        case .dash: return "Dash"
        case .cardano: return "Cardano"
        case .mayaChain: return "MayaChain"
        case .arbitrum: return "Arbitrum"
        case .base: return "Base"
        case .optimism: return "Optimism"
        case .polygon: return "Polygon"
        case .polygonV2: return "Polygon"
        case .blast: return "Blast"
        case .cronosChain: return "CronosChain"
        case .sui: return "Sui"
        case .polkadot: return "Polkadot"
        case .zksync: return "Zksync"
        case .dydx: return "Dydx"
        case .ton: return "Ton"
        case .osmosis: return "Osmosis"
        case .terra: return "Terra"
        case .terraClassic: return "TerraClassic"
        case .noble: return "Noble"
        case .ripple: return "Ripple"
        case .akash: return "Akash"
        case .tron: return "Tron"
        case .ethereumSepolia: return "Ethereum-Sepolia"
        case .zcash: return "Zcash"
        case .mantle: return "Mantle"
        case .hyperliquid: return "Hyperliquid"
        case .sei: return "Sei"
        }
    }
    var feeUnit: String {
        switch self {
        case .thorChain, .thorChainStagenet: return "RUNE"
        case .solana: return "SOL"
        case .ethereum,.avalanche,.base,.blast,.arbitrum,.polygon, .polygonV2,.optimism,.bscChain,.cronosChain, .zksync, .ethereumSepolia, .mantle, .hyperliquid, .sei: return "Gwei"
        case .bitcoin: return "BTC/vbyte"
        case .bitcoinCash: return "BCH/vbyte"
        case .litecoin: return "LTC/vbyte"
        case .dogecoin: return "DOGE/vbyte"
        case .dash: return "DASH/vbyte"
        case .cardano: return "ADA/vbyte"
        case .gaiaChain: return "uatom"
        case .kujira: return "ukuji"
        case .mayaChain: return "CACAO"
        case .sui: return "SUI"
        case .polkadot: return "DOT"
        case .dydx: return "adydx"
        case .ton: return "TON"
        case .osmosis: return "uosmo"
        case .terra: return "uluna"
        case .terraClassic: return "uluna"
        case .noble: return "uusdc"
        case .ripple: return "XRP"
        case .akash: return "uakt"
        case .tron: return "TRX"
        case .zcash: return "ZEC/vbyte"
        }
    }
    
    var ticker: String {
        switch self {
        case .thorChain, .thorChainStagenet: return "RUNE"
        case .solana: return "SOL"
        case .ethereum,.ethereumSepolia: return "ETH"
        case .avalanche: return "AVAX"
        case .bscChain: return "BNB"
        case .bitcoin: return "BTC"
        case .bitcoinCash: return "BCH"
        case .litecoin: return "LTC"
        case .dogecoin: return "DOGE"
        case .gaiaChain: return "UATOM"
        case .kujira: return "UKUJI"
        case .dash: return "DASH"
        case .cardano: return "ADA"
        case .mayaChain: return "CACAO"
        case .arbitrum: return "ARB"
        case .base: return "BASE" 
        case .optimism: return "OP"
        case .polygon: return "MATIC"
        case .polygonV2: return "POL"
        case .blast: return "BLAST"
        case .cronosChain: return "CRO"
        case .sui: return "SUI"
        case .polkadot: return "DOT"
        case .zksync: return "ZK"
        case .dydx: return "ADYDX"
        case .ton: return "TON"
        case .osmosis: return "UOSMO"
        case .terra: return "ULUNA"
        case .terraClassic: return "ULUNC"
        case .noble: return "UUSDC"
        case .ripple: return "XRP"
        case .akash: return "UAKT"
        case .tron: return "TRX"
        case .zcash: return "ZEC"
        case .mantle: return "MNT"
        case .hyperliquid: return "HYPE"
        case .sei: return "SEI"
        }
    }
    
    var swapAsset: String {
        switch self {
        case .thorChain, .thorChainStagenet: return "THOR"
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
        case .cardano: return "ADA"
        case .mayaChain: return "MAYA"
        case .arbitrum: return "ARB"
        case .base: return "BASE"
        case .optimism: return "OP"
        case .polygon: return "MATIC"
        case .polygonV2: return "POL"
        case .blast: return "BLAST"
        case .cronosChain: return "CRO"
        case .sui: return "SUI"
        case .polkadot: return "DOT"
        case .zksync: return "ZK"
        case .dydx: return "DYDX"
        case .ton: return "TON"
        case .osmosis: return "OSMO"
        case .terra: return "LUNA"
        case .terraClassic: return "LUNC"
        case .noble: return "USDC"
        case .ripple: return "XRP"
        case .akash: return "AKT"
        case .tron: return "TRON"
        case .ethereumSepolia: return "ETH"
        case .zcash: return "ZEC"
        case .mantle: return "MANTLE"
        case .hyperliquid: return "HYPE"
        case .sei: return "SEI"
        }
    }
    
    var signingKeyType: KeyType {
        switch self.chainType {
        case .Cosmos, .EVM, .THORChain, .UTXO, .Ripple, .Tron:
            return .ECDSA
        case .Solana, .Polkadot, .Sui, .Ton, .Cardano:
            return .EdDSA
        }
    }
    
    var chainType: ChainType {
        switch self {
        case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .polygonV2, .blast, .cronosChain, .zksync,.ethereumSepolia, .mantle, .hyperliquid, .sei:
            return .EVM
        case .thorChain, .thorChainStagenet, .mayaChain:
            return .THORChain
        case .solana:
            return .Solana
        case .sui:
            return .Sui
        case .cardano:
            return .Cardano
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash, .zcash:
            return .UTXO
        case .gaiaChain, .kujira, .dydx, .osmosis, .terra, .terraClassic, .noble, .akash:
            return .Cosmos
        case .polkadot:
            return .Polkadot
        case .ton:
            return .Ton
        case .ripple:
            return .Ripple
        case .tron:
            return .Tron
        }
    }
    
    var logo: String {
        switch self {
        case .thorChain, .thorChainStagenet:
            return "rune"
        case .solana:
            return "solana"
        case .ethereum,.ethereumSepolia:
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
            return "matic"
        case .polygonV2:
            return "matic"
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
        case .cardano:
            return "ada"
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
            return "dot"
        case .zksync:
            return "zsync_era"
        case .dydx:
            return "dydx"
        case .ton:
            return "ton"
        case .osmosis:
            return "osmo"
        case .terra:
            return "luna"
        case .terraClassic:
            return "lunc"
        case .noble:
            return "noble"
        case .ripple:
            return "xrp"
        case .akash:
            return "akash"
        case .tron:
            return "tron"
        case .zcash:
            return "zec"
        case .mantle:
            return "mantle"
        case .hyperliquid:
            return "hyperliquid"
        case .sei:
            return "sei"
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
            return 81457
        case .arbitrum:
            return 42161
        case .polygon:
            return 137
        case .polygonV2:
            return 137 
        case .optimism:
            return 10
        case .bscChain:
            return 56
        case .cronosChain:
            return 25
        case .zksync:
            return 324
        case .solana:
            return 1151111081099710
        case .ethereumSepolia:
            return 11155111
        case .mantle:
            return 5000
        case .hyperliquid:
            return 999
        case .sei:
            return 1329
        case .thorChain, .thorChainStagenet, .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash, .gaiaChain, .kujira, .mayaChain, .sui, .polkadot, .dydx, .ton, .osmosis, .terra, .terraClassic, .noble, .ripple, .akash, .tron, .zcash, .cardano:
            return nil
        }
    }
    var coinType: CoinType {
        switch self {
        case .bitcoin:
            return CoinType.bitcoin
        case .thorChain, .thorChainStagenet:
            return CoinType.thorchain
        case .solana:
            return CoinType.solana
        case .bitcoinCash:
            return CoinType.bitcoinCash
        case .litecoin:
            return CoinType.litecoin
        case .dogecoin:
            return CoinType.dogecoin
        case .ethereum,.ethereumSepolia:
            return CoinType.ethereum
        case .bscChain:
            return CoinType.smartChain
        case .avalanche:
            return CoinType.avalancheCChain
        case .gaiaChain:
            return CoinType.cosmos
        case .kujira:
            return CoinType.kujira
        case .dash:
            return CoinType.dash
        case .cardano:
            return CoinType.cardano
        case .mayaChain:
            return CoinType.thorchain
        case .arbitrum:
            return CoinType.arbitrum
        case .polygon:
            return CoinType.polygon
        case .polygonV2:
            return CoinType.polygon
        case .base:
            return CoinType.base
        case .optimism:
            return CoinType.optimism
        case .blast:
            return CoinType.blast
        case .cronosChain:
            return CoinType.cronosChain
        case .sui:
            return CoinType.sui
        case .polkadot:
            return CoinType.polkadot
        case .zksync:
            return CoinType.zksync
        case .dydx:
            return CoinType.dydx
        case .ton:
            return CoinType.ton
        case .osmosis:
            return CoinType.osmosis
        case .terra:
            return CoinType.terraV2
        case .terraClassic:
            return CoinType.terra
        case .noble:
            return CoinType.noble
        case .ripple:
            return CoinType.xrp
        case .akash:
            return CoinType.akash
        case .tron:
            return CoinType.tron
        case .zcash:
            return CoinType.zcash
        case .mantle:
            return CoinType.mantle
        case .hyperliquid:
            return CoinType.ethereum
        case .sei:
            return CoinType.ethereum
        }
    }
   
    var isECDSA: Bool {
        return signingKeyType == .ECDSA
    }

    var index: Int {
        return Chain.allCases.firstIndex(of: self) ?? 0
    }
    
    static let example = Chain(name: "Bitcoin")!
    
    var isSwapAvailable: Bool {
        switch self {
        case .thorChain,
                .thorChainStagenet,
                .mayaChain,
                .gaiaChain,
                .kujira,
                .bitcoin,
                .dogecoin,
                .bitcoinCash,
                .litecoin,
                .dash,
                .ripple,
                .avalanche,
                .base,
                .bscChain,
                .ethereum,
                .optimism,
                .polygon,
                .arbitrum,
                .blast,
                .cronosChain,
                .solana,
                .zksync,
                .zcash,
                .mantle,
                .hyperliquid,
                .tron:
            return true
        case .polygonV2,
            .cardano,
            .sui,
            .polkadot,
            .dydx,
            .ton,
            .osmosis,
            .terra,
            .terraClassic,
            .noble,
            .akash,
            .ethereumSepolia,
            .sei:
            return false
        }
    }
    
    var type: ChainType {
        switch self {
        case .thorChain, .thorChainStagenet, .mayaChain:
            return .THORChain
        case .solana:
            return .Solana
        case .ethereum,.avalanche,.base,.blast,.arbitrum,.polygon, .polygonV2,.optimism,.bscChain,.cronosChain, .zksync, .ethereumSepolia, .mantle, .hyperliquid, .sei:
            return .EVM
        case .bitcoin,.bitcoinCash,.litecoin,.dogecoin,.dash, .zcash:
            return .UTXO
        case .cardano:
            return .Cardano
        case .gaiaChain,.kujira, .dydx, .osmosis, .terra, .terraClassic, .noble, .akash:
            return .Cosmos
        case .sui:
            return .Sui
        case .polkadot:
            return .Polkadot
        case .ton:
            return .Ton
        case .ripple:
            return .Ripple
        case .tron:
            return .Tron
        }
    }
}

extension Chain {
    var supportsEip1559: Bool {
        switch self {
        case .bscChain:
            return false
        case .ethereum, .avalanche, .arbitrum, .base, .optimism, .polygon, .polygonV2, .blast, .cronosChain, .ethereumSepolia, .mantle, .hyperliquid, .sei:
            return true
        default:
            return true
        }
    }
    
    /// Indicates if this chain supports pending transaction tracking via sequence numbers (nonce)
    var supportsPendingTransactions: Bool {
        switch self {
        case .thorChain, .thorChainStagenet, .mayaChain, .gaiaChain, .kujira, .osmosis, .dydx, .terra, .terraClassic, .noble, .akash:
            return true
        default:
            return false
        }
    }
    
    static var enabledChains: [Chain] {
        allCases.filter {
            switch $0 {
            case .thorChainStagenet, .polygon:
                return false
            default:
                return true
            }
        }
    }
}
